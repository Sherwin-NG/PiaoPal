# Third-party notices

PiaoPal (飘伴) is independently maintained by Sherwin-NG. Its project identity, release history, and new PiaoPiao artwork are maintained separately. Some implementation and five bundled pet sprite sheets are reused from the open-source projects credited below; PiaoPal does not claim those components as original work.

## macOS implementation

Portions of the Swift, SwiftUI, AppKit, and Metal implementation originate from [hellov3an/OnekoMac](https://github.com/hellov3an/OnekoMac), copyright (c) 2026 v3an, licensed under the MIT License. The full original copyright and MIT permission text are retained in [LICENSE](LICENSE), together with the copyright for PiaoPal additions.

## Existing pet sprite sheets

The Classic, Dog, Tora, Maia, and Vaporwave sprite sheets are retained from [kyrie25/spicetify-oneko/assets/oneko](https://github.com/kyrie25/spicetify-oneko/tree/main/assets/oneko), with byte-identical source files verified during preparation of PiaoPal 0.0.1. PiaoPal displays these as TuanTuan (团团), Dodo (豆豆), BanBan (斑斑), TaoTao (桃桃), and MuMu (暮暮), respectively; renaming does not change authorship. That project derives from [adryd325/oneko.js](https://github.com/adryd325/oneko.js). The upstream sprite project supplies the following MIT notice at [its LICENSE](https://github.com/kyrie25/spicetify-oneko/blob/main/LICENSE):

```text
MIT License

Copyright © 2022 adryd
Copyright © 2026 kyrie25

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

Historical credit retained from the source application's documentation: original **oneko**, Masayuki Koba, 1989. This is a historical credit, not a claim that the contemporary artwork or application was created by that author.

## PiaoPiao artwork

The PiaoPiao (飘飘) character and PiaoPal application icon were created for this project using AI image generation, with reference photographs of Sherwin-NG's own cat supplied by the owner. The original photographs are not included in this repository or application. Source artwork, generation prompts, and assembly details are recorded in `artwork/piaopal/`.

The character's animation is an artistic interpretation. No breed, age, or behavioral accuracy is asserted. New artwork does not remove or supersede the above third-party notices.

## Distribution

The build includes `LICENSE` and `THIRD_PARTY_NOTICES.md` inside `PiaoPal.app/Contents/Resources/`. The DMG additionally includes both documents beside the app. Keep these notices when redistributing the application or relevant source/assets.
