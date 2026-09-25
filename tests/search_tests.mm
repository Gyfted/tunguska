// SPDX-License-Identifier: GPL-2.0-or-later
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import "macos/SearchService.h"
#include "search.h"
#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <random>
#include <stdexcept>
#include <sys/stat.h>
using namespace tunguska::search;
static void require(bool ok,const char*message){if(!ok)throw std::runtime_error(message);}
static void vectorTests(){
    std::mt19937 rng(729);
    for(int trial=0;trial<128;++trial){std::vector<float>a(dimensions),b(dimensions);int expected=0;for(size_t j=0;j<dimensions;++j){a[j]=int(rng()%3)-1;b[j]=int(rng()%3)-1;expected+=int(a[j]*b[j]);}require(dot(pack(a.data()),pack(b.data()))==expected,"packed signed dot must equal dense ternary dot");}
    Index index;std::vector<std::vector<float>> dense;
    for(int i=0;i<1024;++i){std::vector<float>v(dimensions);for(float&x:v)x=float(int(rng()%101)-50);index.add({"p"+std::to_string(i),"title","Text."},"test text",v);dense.push_back(v);}
    std::vector<float>query(dimensions);for(float&x:query)x=float(int(rng()%101)-50);
    auto exact=index.meaning(query,20,true),candidate=index.meaning(query,20,false);
    require(exact.hits.size()==20&&candidate.hits.size()==20,"semantic result sizes");
    for(const Hit& h:candidate.hits)require(std::isfinite(h.score)&&h.id<1024,"bounded semantic result");
    std::vector<Hit> oracle;double queryNorm=0;for(float x:query)queryNorm+=double(x)*x;
    for(size_t i=0;i<dense.size();++i){double product=0,norm=0;for(size_t j=0;j<dimensions;++j){product+=double(query[j])*dense[i][j];norm+=double(dense[i][j])*dense[i][j];}oracle.push_back({uint32_t(i),product/std::sqrt(queryNorm*norm)});}
    std::sort(oracle.begin(),oracle.end(),[](const Hit&a,const Hit&b){return a.score>b.score||(a.score==b.score&&a.id<b.id);});
    size_t overlap=0;
    for(size_t i=0;i<20;++i){require(exact.hits[i].id==oracle[i].id&&std::fabs(exact.hits[i].score-oracle[i].score)<1e-6,"Accelerate baseline agrees with independent double cosine oracle");for(const auto&h:candidate.hits)if(h.id==oracle[i].id)++overlap;}
    require(overlap>=19,"seeded approximate search recall regression");
    query[0]=NAN;bool rejected=false;try{index.meaning(query);}catch(const std::invalid_argument&){rejected=true;}require(rejected,"reject nonfinite embeddings");
    rejected=false;try{index.add({"p","t","x"},"x",{1});}catch(const std::invalid_argument&){rejected=true;}require(rejected&&index.passages().size()==1024,"invalid add preserves index size");
    require(index.keywords("").hits.empty(),"empty keyword query");
    std::vector<float>zero(dimensions);require(pack(zero.data()).inverseNorm==0&&index.meaning(zero).hits.empty(),"zero vectors");
}
static void writePDF(NSString *path){
    CGRect box=CGRectMake(0,0,400,300);CGContextRef context=CGPDFContextCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],&box,nullptr);require(context,"PDF fixture context");
    CGPDFContextBeginPage(context,nullptr);[NSGraphicsContext saveGraphicsState];[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO]];
    [@"Warranty for a sapphire bicycle and its wheels." drawAtPoint:NSMakePoint(20,180) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:14]}];
    [NSGraphicsContext restoreGraphicsState];CGPDFContextEndPage(context);CGPDFContextClose(context);CGContextRelease(context);
}
static void serviceTests(){
    char dir[]="/tmp/tunguska-search-tests-XXXXXX";require(mkdtemp(dir),"fixture folder");
    struct Cleanup{std::string path;~Cleanup(){std::filesystem::remove_all(path);}}cleanup{dir};NSString *root=[NSString stringWithUTF8String:dir];
    auto write=[&](NSString *name,NSString *text){require([text writeToFile:[root stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:nil],"write fixture");};
    write(@"invoice.md",[@"A receipt for a blue sofa. The navy couch was delivered to reception. Furniture purchase invoice. " stringByAppendingString:[[@"Furniture delivery. " stringByPaddingToLength:600 withString:@"Furniture delivery. " startingAtIndex:0] stringByAppendingString:@"latepassagekeyword"]]);
    write(@"meeting.txt",@"We discussed raising subscription prices and the new annual pricing plan.");
    write(@"accent.txt",@"Café résumé. 東京の旅行 計画. Security privacy and encryption.");
    write(@".hidden.txt",@"secret hiddenword");write(@"unsupported.sh",@"ignoredword");
    write(@"broken.pdf",@"invalid PDF");writePDF([root stringByAppendingPathComponent:@"bicycle.pdf"]);
    std::filesystem::create_symlink("invoice.md",std::string(dir)+"/linked.txt");
    std::filesystem::create_directory(std::string(dir)+"/nested");
    std::filesystem::create_directory_symlink("nested",std::string(dir)+"/linked-dir");
    require(mkfifo((std::string(dir)+"/pipe.txt").c_str(),0600)==0,"fifo fixture");
    std::atomic<bool>cancel{false};SearchService *service=[SearchService indexFolder:[NSURL fileURLWithPath:root isDirectory:YES] cancel:cancel progress:{} semantic:YES];
    require(service.fileCount==4&&service.passageCount==4,"supported real files only");require(service.skippedCount>=3,"skipped inputs counted");
    NSDictionary *hits=[service search:@"sapphire bicycle" meaning:NO reference:NO];require([hits[@"hits"] count]==1&&[hits[@"hits"][0][@"page"] intValue]==1,"PDF text and page number");
    hits=[service search:@"latepassagekeyword" meaning:NO reference:NO];
    require([hits[@"hits"][0][@"snippet"] containsString:@"latepassagekeyword"],"keyword snippet includes a match near the end of a passage");
    for(NSString *query in @[@"receipt couch",@"pricing plan",@"cafe resume",@"東京の旅行",@"security OR privacy",@"\"; DROP TABLE documents; --",@"unmatched"]){
        NSDictionary *a=[service search:query meaning:NO reference:NO],*b=[service search:query meaning:NO reference:YES];
        require([[a[@"hits"] valueForKey:@"id"] isEqual:[b[@"hits"] valueForKey:@"id"]],"SQLite/native keyword IDs agree");
        for(NSUInteger i=0;i<[a[@"hits"] count];++i)require(std::fabs([a[@"hits"][i][@"score"] doubleValue]-[b[@"hits"][i][@"score"] doubleValue])<1e-8,"BM25 score equality");
    }
    require(service.semanticCount==4,"offline Apple embeddings available on test host");
    NSDictionary *semantic=[service search:@"proof of purchase for living room furniture" meaning:YES reference:NO];require([semantic[@"hits"][0][@"title"] isEqual:@"invoice.md"],"paraphrase retrieves furniture receipt");
    NSDictionary *report=[service benchmark:@[@"receipt",@"pricing",@"cafe",@"bicycle"] meaning:NO rounds:3 cancel:cancel];require([report[@"quality_gate_passed"] boolValue],"benchmark quality gate");
    NSDictionary *empty=[service benchmark:@[@"nonexistentword"] meaning:NO rounds:3 cancel:cancel];require(![empty[@"two_times_target_met"] boolValue],"empty result benchmark cannot claim acceptance");
    require([report[@"corpus_canonical_sha256"] length]==64&&[report[@"query_sequence_sha256"] length]==64,"benchmark fingerprints");
    for(NSString *query in @[[ @"x" stringByPaddingToLength:4097 withString:@"x" startingAtIndex:0],[@"x " stringByPaddingToLength:130 withString:@"x " startingAtIndex:0]]){
        for(BOOL reference:{NO,YES}){bool tooLong=false;try{[service search:query meaning:NO reference:reference];}catch(const std::invalid_argument&){tooLong=true;}require(tooLong,"both engines enforce query limits");}
    }
    require([service canReveal:[root stringByAppendingPathComponent:@"invoice.md"]],"reveal selected file");
    require(![service canReveal:@"/etc/passwd"]&&![service canReveal:[root stringByAppendingPathComponent:@"linked.txt"]],"reveal rejects outside root and symlink");
    std::atomic<bool> duringBuild{false};bool interrupted=false;
    try{[SearchService indexFolder:[NSURL fileURLWithPath:root isDirectory:YES] cancel:duringBuild progress:[&](NSString *){duringBuild.store(true);} semantic:NO];}
    catch(const std::runtime_error&){interrupted=true;}
    require(interrupted&&duringBuild.load(),"cancellation after enumeration starts");
    cancel.store(true);bool rejected=false;try{[SearchService indexFolder:[NSURL fileURLWithPath:root isDirectory:YES] cancel:cancel progress:{} semantic:NO];}catch(const std::runtime_error&){rejected=true;}require(rejected,"cancelled rebuild fails transactionally");
    require([[service search:@"receipt" meaning:NO reference:NO][@"hits"] count]>0,"previous index remains usable");
}
int main(){@autoreleasepool{try{vectorTests();serviceTests();std::cout<<"PASS local search: packed arithmetic, SQLite score/result parity, Unicode, PDF extraction, paraphrases, boundaries, safe files, cancellation and benchmark gates\n";}catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<'\n';return 1;}}}
