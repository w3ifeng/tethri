# Study rain source

`study-rain-source.mp3` is `3.mp3` from Ylmir's **Rain (loopable)** pack:
https://opengameart.org/content/rain-loopable

Original archive: https://opengameart.org/sites/default/files/Rain%20MP3.zip
License: CC0 1.0 Universal, https://creativecommons.org/publicdomain/zero/1.0/

The author recorded rain at a window and processed it into stereo loops.
`scripts/generate-rain.py` removes low rumble, softens high frequencies,
normalizes to a quiet level and crossfades the loop boundary. It produces the
bundled `rain.wav`; it does not synthesize noise. No runtime download is needed.
