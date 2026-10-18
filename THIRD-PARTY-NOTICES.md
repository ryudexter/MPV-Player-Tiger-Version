# Third-party notices

`LICENSE` (MIT) covers this repository's own files. The files below come from
other projects and keep their own licenses.

| Files | From | License | Changed here |
|---|---|---|---|
| `scripts/thumbfast.lua` | [po5/thumbfast](https://github.com/po5/thumbfast) | MPL-2.0 | yes — one `LOCAL PATCH` (finding mpv on Windows and Linux), marked in the file |
| `scripts/skiptosilence.lua` | [detuur/mpv-scripts](https://github.com/detuur/mpv-scripts) | MIT | yes — see the `LOCAL PATCH` note at the top of the file |
| `scripts/webm.lua` | [ekisu/mpv-webm](https://github.com/ekisu/mpv-webm) | MIT | yes — every change is marked `LOCAL` |
| `shaders/Anime4K_*.glsl` | [bloc97/Anime4K](https://github.com/bloc97/Anime4K) v4.0.1 | MIT | no |
| `app/icons/*.icns`, `app/icons/mpv.ico`, `app/icons/mpv.png` | the mpv logo, from [mpv-player/mpv](https://github.com/mpv-player/mpv) | mpv's license (GPLv2+ for mpv as a whole; see its [Copyright](https://github.com/mpv-player/mpv/blob/master/Copyright) file) | the document icons put the logo on a tile with the file type; `mpv.ico` and `mpv.png` are `mpv.icns` resized, for Windows and Linux |
| `sounds/*.wav` | macOS's own Finder ("move to trash") and Dock ("poof") system sounds | Apple's; not covered by `LICENSE` | short pieces, slowed and quieter — `sounds/make-trash-sounds.sh` shows exactly how, and rebuilds them from any Mac's own copy |

`field-guide.html` loads the IBM Plex fonts from Google Fonts (SIL Open Font
License); they are not stored here.

---

## thumbfast — MPL-2.0

`scripts/thumbfast.lua` is subject to the terms of the Mozilla Public License,
v. 2.0. You can obtain a copy at <https://mozilla.org/MPL/2.0/>. Its source is
the file itself, including the one `LOCAL PATCH` block added here, which is
under the same license.

## mpv-scripts (skiptosilence) — MIT

```
MIT License

Copyright (c) 2018 Arthur Jochems

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## mpv-webm — MIT

```
MIT License

Copyright (c) 2020 ekisu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Anime4K — MIT

The full notice is also at the top of each shader file.

```
MIT License

Copyright (c) 2019-2021 bloc97

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
