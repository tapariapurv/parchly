# Parchly product film

The 37-second demo on the website (`docs/assets/film.mp4`), built in code with [HyperFrames](https://github.com/heygen-com/hyperframes) and GSAP. Picture is `index.html`; all timing, the score and the sound effects come from `scripts/sound.py`.

```sh
cd marketing/film
mkdir -p assets/fonts && cp /System/Library/Fonts/{NewYork,NewYorkItalic,SFNS,SFNSMono}.ttf assets/fonts/   # Apple fonts, not committed
python3 scripts/sound.py        # writes assets/cues.js and assets/score.m4a (needs numpy + ffmpeg)
npx hyperframes render --quality delivery --output renders/parchly-film.mp4
ffmpeg -i renders/parchly-film.mp4 -c copy -movflags +faststart ../../docs/assets/film.mp4
```
