// SPDX-License-Identifier: GPL-2.0-or-later
#import "SearchService.h"
#import <NaturalLanguage/NaturalLanguage.h>
#import <PDFKit/PDFKit.h>
#include "search.h"
#include <sqlite3.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <CommonCrypto/CommonDigest.h>
#include <unistd.h>

namespace ts=tunguska::search;
using Clock=std::chrono::steady_clock;
static double elapsed(Clock::time_point start){return std::chrono::duration<double,std::milli>(Clock::now()-start).count();}
static NSString *str(const std::string& s){return [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding]?:@"";}
static std::string utf8(NSString *s){return s.UTF8String?:"";}
static NSString *canonical(NSString *s) {
    NSString *folded=[[s stringByFoldingWithOptions:NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]] lowercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    NSMutableString *result=[NSMutableString string];
    for(NSString *word in [folded componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]) {
        if(!word.length)continue;
        // Keep the same bounded tokenization in the native and SQLite indexes.
        if([word lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>256)continue;
        if(result.length)[result appendString:@" "];[result appendString:word];
    }
    return result;
}
static NSString *fingerprint(const std::vector<std::string>& strings) {
    CC_SHA256_CTX ctx; CC_SHA256_Init(&ctx);
    for (const auto& value:strings) { // Length prefixes make the sequence unambiguous.
        std::string size=std::to_string(value.size())+":";
        CC_SHA256_Update(&ctx,size.data(),CC_LONG(size.size()));
        CC_SHA256_Update(&ctx,value.data(),CC_LONG(value.size()));
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(digest,&ctx);
    NSMutableString *hex=[NSMutableString string];for(unsigned char byte:digest)[hex appendFormat:@"%02x",byte];return hex;
}
static NSString *hardware() {
    char name[256]={};size_t length=sizeof(name);
    return sysctlbyname("machdep.cpu.brand_string",name,&length,nullptr,0)==0?@(name):@"Unavailable";
}
static std::vector<float> embed(NLEmbedding *model,NSString *text) {
    if(!model)return {};
    std::vector<float> v(ts::dimensions);
    if(![model getVector:v.data() forString:text])return {};
    return v;
}
static void checkCancel(const std::atomic<bool>& flag){if(flag.load())throw std::runtime_error("Indexing or benchmark cancelled");}
static void sqlCheck(int code,sqlite3 *db){if(code!=SQLITE_OK&&code!=SQLITE_DONE&&code!=SQLITE_ROW)throw std::runtime_error(sqlite3_errmsg(db));}
static NSData *boundedRead(int root,NSString *relative,size_t limit) {
    struct File {int fd;~File(){if(fd>=0)close(fd);}} file{dup(root)};
    NSArray<NSString *> *parts=[relative componentsSeparatedByString:@"/"];
    if(!parts.count||parts.count>256)throw std::runtime_error("Invalid relative file path");
    for(NSUInteger i=0;i<parts.count;++i){
        NSString *part=parts[i];
        if(!part.length||[part isEqual:@"."]||[part isEqual:@".."])throw std::runtime_error("Invalid relative file path");
        int flags=O_RDONLY|O_NONBLOCK|O_NOFOLLOW|O_CLOEXEC;
        if(i+1<parts.count)flags|=O_DIRECTORY;
        int next=openat(file.fd,part.fileSystemRepresentation,flags);
        if(next<0)throw std::runtime_error("File cannot be read safely (links are excluded)");
        close(file.fd);file.fd=next;
    }
    if(file.fd<0)throw std::runtime_error("File cannot be read safely");
    struct stat info;if(fstat(file.fd,&info)||!S_ISREG(info.st_mode)||info.st_size<0||uint64_t(info.st_size)>limit)
        throw std::runtime_error("Not a regular file or file exceeds the size limit");
    NSMutableData *data=[NSMutableData data];char buffer[65536];
    while(true){ssize_t n=read(file.fd,buffer,sizeof(buffer));if(n<0){if(errno==EINTR)continue;throw std::runtime_error("Read failed");}if(!n)break;
        if(size_t(n)>limit-data.length)throw std::runtime_error("File grew beyond the size limit");[data appendBytes:buffer length:NSUInteger(n)];}
    return data;
}
@implementation SearchService {
    std::unique_ptr<ts::Index> _index;
    NLEmbedding *_model;
    sqlite3 *_db;
    sqlite3_stmt *_referenceStatement;
    NSUInteger _fileCount,_skippedCount;
    NSString *_rootPath;
    double _buildMilliseconds;
    NSMutableArray<NSString *> *_warnings;
}
- (void)dealloc{if(_referenceStatement)sqlite3_finalize(_referenceStatement);if(_db)sqlite3_close(_db);}
- (NSUInteger)passageCount{return _index?_index->passages().size():0;}
- (NSUInteger)fileCount{return _fileCount;}
- (NSUInteger)skippedCount{return _skippedCount;}
- (NSUInteger)semanticCount{return _index?_index->semanticCount():0;}
- (NSString *)rootPath{return _rootPath;}
- (double)buildMilliseconds{return _buildMilliseconds;}
- (NSArray<NSString *> *)warnings{return [_warnings copy];}
- (NSString *)modelDescription{return _model?[NSString stringWithFormat:@"Apple English sentence embedding · revision %lu · 512 dimensions",(unsigned long)_model.revision]:@"English sentence model unavailable; keyword search works";}
+ (instancetype)indexFolder:(NSURL *)folder cancel:(const std::atomic<bool>&)cancel progress:(const std::function<void(NSString *)>&)progress semantic:(BOOL)semantic {
    auto start=Clock::now();if(!folder.isFileURL)throw std::invalid_argument("Choose a local folder");
    SearchService *service=[[SearchService alloc] init];service->_index=std::make_unique<ts::Index>();service->_warnings=[NSMutableArray array];
    service->_rootPath=folder.URLByResolvingSymlinksInPath.path;
    struct Root {int fd;~Root(){if(fd>=0)close(fd);}} root{open(service->_rootPath.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)};
    if(root.fd<0)throw std::runtime_error("Cannot open the selected directory");
    NSNumber *directory=nil;NSError *error=nil;
    if(![folder getResourceValue:&directory forKey:NSURLIsDirectoryKey error:&error]||!directory.boolValue)throw std::invalid_argument("Choose a readable folder");
    service->_model=semantic?[NLEmbedding sentenceEmbeddingForLanguage:NLLanguageEnglish]:nil;
    if(service->_model.dimension!=ts::dimensions)service->_model=nil;
    NSSet *extensions=[NSSet setWithArray:@[@"txt",@"md",@"markdown",@"pdf"]];
    NSArray *keys=@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLIsDirectoryKey,NSURLIsPackageKey];
    NSDirectoryEnumerator<NSURL *> *enumerator=[NSFileManager.defaultManager enumeratorAtURL:folder includingPropertiesForKeys:keys options:NSDirectoryEnumerationSkipsHiddenFiles|NSDirectoryEnumerationSkipsPackageDescendants errorHandler:^BOOL(NSURL *url,NSError *failure){
        ++service->_skippedCount;if(service->_warnings.count<100)[service->_warnings addObject:[NSString stringWithFormat:@"%@: %@",url.lastPathComponent,failure.localizedDescription]];return YES;}];
    if(!enumerator)throw std::runtime_error("Cannot enumerate this folder");
    size_t totalText=0,visited=0;
    for(NSURL *url in enumerator){@autoreleasepool{
        checkCancel(cancel);
        if(++visited>200000)throw std::runtime_error("Folder has more than 200,000 entries; choose a smaller folder");
        NSNumber *link=nil;[url getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];if(link.boolValue){[enumerator skipDescendants];++service->_skippedCount;continue;}
        NSNumber *isDirectory=nil;[url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];if(isDirectory.boolValue)continue;
        NSString *extension=url.pathExtension.lowercaseString;if(![extensions containsObject:extension])continue;
        NSString *path=url.URLByResolvingSymlinksInPath.path;
        if(![path hasPrefix:[service->_rootPath stringByAppendingString:@"/"]]){++service->_skippedCount;continue;}
        if(progress)progress([NSString stringWithFormat:@"Reading %@ · %lu passages",url.lastPathComponent,(unsigned long)service.passageCount]);
        NSMutableArray<NSString *> *pages=[NSMutableArray array];
        @try {try {
            NSString *relative=[path substringFromIndex:service->_rootPath.length+1];
            NSData *data=boundedRead(root.fd,relative,[extension isEqual:@"pdf"]?32*1024*1024:8*1024*1024);
            if([extension isEqual:@"pdf"]){
                PDFDocument *pdf=[[PDFDocument alloc] initWithData:data];
                if(!pdf||pdf.isLocked)throw std::runtime_error("PDF is invalid or password-protected");
                if(pdf.pageCount>1000)throw std::runtime_error("PDF exceeds the 1,000-page limit");
                size_t extracted=0;
                for(NSUInteger page=0;page<pdf.pageCount;++page){checkCancel(cancel);NSString *text=[pdf pageAtIndex:page].string?:@"";
                    extracted+=text.length;if(extracted>8*1024*1024)throw std::runtime_error("Extracted PDF text exceeds the limit");[pages addObject:text];}
            }else{
                NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if(!text)text=[[NSString alloc] initWithData:data encoding:NSUTF16StringEncoding];
                if(!text)throw std::runtime_error("Text must use UTF-8 or UTF-16 encoding");
                if([text rangeOfString:[NSString stringWithFormat:@"%C",(unichar)0]].location!=NSNotFound)throw std::runtime_error("Binary content is not indexed");
                [pages addObject:text];
            }
        }catch(const std::exception& e){checkCancel(cancel);++service->_skippedCount;if(service->_warnings.count<100)[service->_warnings addObject:[NSString stringWithFormat:@"%@: %s",url.lastPathComponent,e.what()]];continue;}}
        @catch(NSException *exception){++service->_skippedCount;if(service->_warnings.count<100)[service->_warnings addObject:[NSString stringWithFormat:@"%@: PDF/text extraction failed",url.lastPathComponent]];continue;}
        size_t before=service.passageCount;
        for(NSUInteger page=0;page<pages.count;++page){
            NSString *text=pages[page];NSUInteger offset=0;
            while(offset<text.length){
                checkCancel(cancel);
                NSUInteger length=std::min(NSUInteger(1200),text.length-offset);
                NSRange range=[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(offset,length)];
                if(NSMaxRange(range)<text.length){NSRange boundary=[text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet options:NSBackwardsSearch range:NSMakeRange(offset+length/2,length/2)];if(boundary.location!=NSNotFound)range.length=boundary.location-offset+1;}
                NSString *part=[[text substringWithRange:range] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];offset=NSMaxRange(range);
                if(!part.length)continue;
                NSString *clean=canonical(part);if(!clean.length)continue;
                totalText += [part lengthOfBytesUsingEncoding:NSUTF8StringEncoding];if(totalText>128*1024*1024)throw std::runtime_error("Extracted text exceeds 128 MiB; choose a smaller folder");
                auto vector=embed(service->_model,part);
                service->_index->add({utf8(path),utf8(url.lastPathComponent),utf8(part),[extension isEqual:@"pdf"]?int(page+1):0},utf8(clean),vector);
            }
        }
        if(service.passageCount>before)++service->_fileCount;else{++service->_skippedCount;if(service->_warnings.count<100)[service->_warnings addObject:[url.lastPathComponent stringByAppendingString:@": no readable text (scans need OCR)"]];}
    }}
    checkCancel(cancel);service->_buildMilliseconds=elapsed(start);return service;
}
- (void)prepareReference {
    if(_db)return;
    sqlCheck(sqlite3_open(":memory:",&_db),_db);
    try {
        sqlCheck(sqlite3_exec(_db,"CREATE VIRTUAL TABLE documents USING fts5(body, tokenize='ascii'); BEGIN",nullptr,nullptr,nullptr),_db);
        sqlite3_stmt *statement=nullptr;sqlCheck(sqlite3_prepare_v2(_db,"INSERT INTO documents(rowid,body) VALUES(?,?)",-1,&statement,nullptr),_db);
        struct Statement {sqlite3_stmt *p;~Statement(){sqlite3_finalize(p);}} guard{statement};
        const auto& texts=_index->canonicalTexts();
        for(size_t i=0;i<texts.size();++i){sqlite3_bind_int64(statement,1,i+1);sqlite3_bind_text(statement,2,texts[i].c_str(),int(texts[i].size()),SQLITE_TRANSIENT);sqlCheck(sqlite3_step(statement),_db);sqlite3_reset(statement);}
        sqlCheck(sqlite3_exec(_db,"COMMIT; INSERT INTO documents(documents) VALUES('optimize')",nullptr,nullptr,nullptr),_db);
        sqlCheck(sqlite3_prepare_v2(_db,"SELECT rowid, -rank FROM documents WHERE documents MATCH ? ORDER BY rank LIMIT 20",-1,&_referenceStatement,nullptr),_db);
    }catch(...){sqlite3_close(_db);_db=nullptr;throw;}
}
- (NSDictionary *)search:(NSString *)query meaning:(BOOL)meaning reference:(BOOL)reference {
    const auto start=Clock::now();
    if(!query || [query lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>4096)throw std::invalid_argument("Use a shorter search query");
    ts::QueryResult found;NSString *clean=nil;
    if(meaning){
        if(!_model)throw std::runtime_error("English sentence embeddings are unavailable on this Mac");
        if(query.length){auto q=embed(_model,query);if(!q.empty())found=_index->meaning(q,20,reference);}
    }else{
        clean=canonical(query);
        if(reference){
            [self prepareReference];
            auto words=ts::tokens(utf8(clean));if(words.size()>64)throw std::invalid_argument("Use at most 64 query terms");
            std::sort(words.begin(),words.end());words.erase(std::unique(words.begin(),words.end()),words.end());
            std::string expression;
            for(const auto& word:words){if(!expression.empty())expression+=" OR ";expression+='"';expression+=word;expression+='"';}
            if(!expression.empty()){
                sqlite3_stmt *statement=_referenceStatement;
                struct Reset{sqlite3_stmt*p;~Reset(){sqlite3_reset(p);sqlite3_clear_bindings(p);}}guard{statement};sqlite3_bind_text(statement,1,expression.c_str(),-1,SQLITE_TRANSIENT);
                int code;while((code=sqlite3_step(statement))==SQLITE_ROW)found.hits.push_back({uint32_t(sqlite3_column_int64(statement,0)-1),sqlite3_column_double(statement,1)});sqlCheck(code,_db);
            }
        }else found=_index->keywords(utf8(clean));
    }
    NSMutableArray *hits=[NSMutableArray array];
    NSArray<NSString *> *snippetTerms=clean.length?[clean componentsSeparatedByString:@" "]:@[];
    for(const auto& hit:found.hits){
        const auto& p=_index->passages().at(hit.id);NSString *text=str(p.text);NSUInteger offset=0;
        for(NSString *term in snippetTerms){NSRange match=[text rangeOfString:term options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch|NSWidthInsensitiveSearch];if(match.location!=NSNotFound){offset=match.location>96?match.location-96:0;break;}}
        NSRange excerpt=[text rangeOfComposedCharacterSequencesForRange:NSMakeRange(offset,std::min(NSUInteger(320),text.length-offset))];
        NSString *snippet=[text substringWithRange:excerpt];
        if(excerpt.location)snippet=[@"…" stringByAppendingString:snippet];
        if(NSMaxRange(excerpt)<text.length)snippet=[snippet stringByAppendingString:@"…"];
        [hits addObject:@{@"id":@(hit.id),@"path":str(p.path),@"title":str(p.title),@"page":@(p.page),@"snippet":snippet,@"score":@(hit.score)}];
    }
    return @{@"hits":hits,@"milliseconds":@(elapsed(start)),@"candidates":@(found.candidates)};
}
- (NSDictionary *)benchmark:(NSArray<NSString *> *)queries meaning:(BOOL)meaning rounds:(NSUInteger)rounds cancel:(const std::atomic<bool>&)cancel {
    if(!queries.count || queries.count>100 || rounds<3 || rounds>31)throw std::invalid_argument("Invalid benchmark size");
    if(!meaning)[self prepareReference];
    NSMutableArray *measurements=[NSMutableArray array];std::vector<double> fast,base;size_t common=0,expected=0,orderedMatches=0;double maxScoreError=0,minRecall=1;
    // Both paths warm once, neither caches query vectors or final results.
    for(NSString *q in queries){checkCancel(cancel);[self search:q meaning:meaning reference:NO];[self search:q meaning:meaning reference:YES];}
    for(NSUInteger r=0;r<rounds;++r)for(NSUInteger j=0;j<queries.count;++j){@autoreleasepool{
        checkCancel(cancel);NSString *q=queries[j];NSDictionary *a,*b;
        if((r+j)%2){a=[self search:q meaning:meaning reference:NO];b=[self search:q meaning:meaning reference:YES];}
        else{b=[self search:q meaning:meaning reference:YES];a=[self search:q meaning:meaning reference:NO];}
        double f=[a[@"milliseconds"] doubleValue],s=[b[@"milliseconds"] doubleValue];fast.push_back(f);base.push_back(s);
        NSMutableDictionary *scores=[NSMutableDictionary dictionary];for(NSDictionary *h in a[@"hits"])scores[h[@"id"]]=h[@"score"];
        size_t queryCommon=0;
        for(NSDictionary *h in b[@"hits"]){++expected;NSNumber *v=scores[h[@"id"]];if(v){++common;++queryCommon;maxScoreError=std::max(maxScoreError,std::fabs(v.doubleValue-[h[@"score"] doubleValue]));}}
        const NSUInteger referenceCount=[b[@"hits"] count];
        if(referenceCount)minRecall=std::min(minRecall,double(queryCommon)/referenceCount);
        if([[a[@"hits"] valueForKey:@"id"] isEqual:[b[@"hits"] valueForKey:@"id"]])++orderedMatches;
        [measurements addObject:@{@"round":@(r),@"query_index":@(j),@"native_ms":@(f),@"reference_ms":@(s),@"native_ids":[a[@"hits"] valueForKey:@"id"],@"reference_ids":[b[@"hits"] valueForKey:@"id"]}];
    }}
    auto percentile=[](std::vector<double> v,double p){std::sort(v.begin(),v.end());return v[size_t((v.size()-1)*p)];};
    double fm=percentile(fast,.5),bm=percentile(base,.5),recall=expected?double(common)/expected:1;
    bool quality=expected>0 && (meaning?(recall>=.98&&minRecall>=.95):(recall==1&&maxScoreError<1e-8));
    std::vector<std::string> queryStrings;for(NSString *q in queries)queryStrings.push_back(utf8(q));
    return @{@"hardware":hardware(),@"os":NSProcessInfo.processInfo.operatingSystemVersionString,
        @"architecture":@(
#if defined(__arm64__)
        "arm64"
#else
        "x86_64"
#endif
        ),@"sqlite_version":@(sqlite3_libversion()),@"corpus_canonical_sha256":fingerprint(_index->canonicalTexts()),
        @"query_sequence_sha256":fingerprint(queryStrings),@"min_query_recall_at_20":@(minRecall),
        @"ordered_results_match_fraction":@(double(orderedMatches)/measurements.count),
        @"format":@"tunguska-search-benchmark-v1",@"mode":meaning?@"meaning":@"keywords",@"reference":meaning?@"Accelerate FP32 exhaustive cosine":@"SQLite FTS5 BM25 ORDER BY rank",@"documents":@(_fileCount),@"passages":@(self.passageCount),@"rounds":@(rounds),@"query_count":@(queries.count),@"model":self.modelDescription,@"indexing_ms":@(_buildMilliseconds),@"native_median_ms":@(fm),@"reference_median_ms":@(bm),@"native_p90_ms":@(percentile(fast,.9)),@"reference_p90_ms":@(percentile(base,.9)),@"speedup":@(fm>0?bm/fm:0),@"recall_at_20":@(recall),@"max_matched_score_error":@(maxScoreError),@"quality_gate_passed":@(quality),@"two_times_target_met":@(quality&&fm>0&&bm/fm>=2),@"fp32_vector_bytes":@(_index->vectorBytes()),@"additional_packed_bytes":@(_index->packedBytes()),@"samples":measurements,@"timing_scope":@"Query string to materialized title/path/page/snippet results. Includes canonicalization or fresh sentence embedding, scoring, top-k and snippets. Excludes initial indexing, reference index preparation, UI drawing, disk cold-start and model loading. No query-result cache. Alternating path order; one warmup per query/path. Keyword engines use identical canonical tokens and BM25; meaning uses ternary shortlist then original FP32 reranking, compared with full FP32 scan. Not a comparison with HNSW, Spotlight or other commercial search products."};
}
- (BOOL)canReveal:(NSString *)path {
    if(![path hasPrefix:[_rootPath stringByAppendingString:@"/"]])return NO;
    NSURL *url=[NSURL fileURLWithPath:path];if(![url.URLByResolvingSymlinksInPath.path isEqual:path])return NO;
    struct stat info;return lstat(path.fileSystemRepresentation,&info)==0&&S_ISREG(info.st_mode);
}
@end
