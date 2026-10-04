第三方组件声明
================

本文件列出 PaneSpace 分发物中包含的第三方组件及其许可要求。

Sparkle 2.10.0
--------------

- 用途：应用内更新（检查 appcast、下载、验签、替换、重启）
- 来源：<https://github.com/sparkle-project/Sparkle>
- 许可：MIT
- 随附位置：`PaneSpace.app/Contents/Frameworks/Sparkle.framework`
- 取得方式：Swift Package Manager，版本以 `exact:` 固定为 2.10.0

Sparkle 的完整版权声明与许可全文（MIT）：

```
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

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

MIT 与 PaneSpace 自身的 MIT 许可兼容，随闭源或开源分发均只需保留上述声明。

上游把该框架以通用二进制（arm64 + x86_64）发布。PaneSpace 的构建脚本用 `lipo`
将其裁为 arm64（见 `scripts/build-app.sh`），并在裁剪之后重新签名；分发物中不包含
x86_64 架构的 Sparkle 代码。
