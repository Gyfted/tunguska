# Source and binary release procedure

This fork currently publishes source only. The local `.app` is a development
preview, not a notarized distribution. Do not claim upstream endorsement.

Before publishing a binary release:

1. Review any newly incorporated code, libraries, artwork or documentation for
   compatible licensing. Preserve their original copyright and license notices.
2. Add dated notices to modified original files. Keep AUTHORS, NOTICE.md and
   source provenance accurate; distinguish original work from fork changes.
3. Run `make test sanitize security-check` and build the app from a clean checkout.
   Record the commit, architecture, compiler and macOS versions used.
4. Tag the exact source commit used to build the binary. Publish a complete
   corresponding source archive from that tag, including all required source,
   interface files, resources, license notices and build/installation scripts.
   Any dependencies needed beyond system components must be available under
   their applicable terms. Do not rely on an unrelated or moving main branch.
5. Provide the binary and matching source download together on the same release
   page. Include LICENSE, AUTHORS and NOTICE.md with the app/distribution, and
   make the GPL and warranty information accessible in the app.
6. Check signing, sandboxing and notarization requirements separately. They do
   not replace GPL compliance. Update the documented security limitations.

This procedure uses accompanying source rather than a written source offer.
A written-offer route has additional obligations, including duration, and
should not be substituted casually. Preserve source for every distributed
binary release and keep recipients' redistribution and modification rights.

References:

- GNU GPLv2, especially sections 1–3 and 6:
  https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
- GNU licensing FAQ: https://www.gnu.org/licenses/gpl-faq.en.html
