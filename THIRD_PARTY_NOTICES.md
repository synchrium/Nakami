# Third-party notices

## libarchive

Nakami uses [libarchive](https://www.libarchive.org/) to read and write archives.

- The app links to the copy of libarchive that ships with macOS (`/usr/lib/libarchive.2.dylib`).
  Nakami does not include a copy of the libarchive library itself.
- This repository contains two libarchive header files, `CArchive/archive.h` and
  `CArchive/archive_entry.h` (from libarchive 3.8.10), so that Swift can call libarchive.
  Their original copyright notices are kept at the top of each file.

libarchive is distributed under the following license (BSD 2-Clause):

```
Copyright (c) 2003-2018 Tim Kientzle and the libarchive contributors
  archive.h:       Copyright (c) 2003-2010 Tim Kientzle
  archive_entry.h: Copyright (c) 2003-2008 Tim Kientzle
                   Copyright (c) 2016 Martin Matuska
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer
   in this position and unchanged.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

The same notice is shown in the app under **Nakami → About Nakami**.
