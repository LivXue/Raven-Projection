# Blink artwork

The closed-eye source was made with the built-in `image_gen` editing tool
from `assets/raven-chibi-transparent.png`. The result is stored in
`assets/raven-chibi-closed.png` at the same 1254 x 1254 resolution.

`build-blink-assets.ps1` extracts two eye regions, feathers their outer
edges, scales them, and crops a 79 x 43 patch into `package/raven-blink.png`.
This small transparent overlay is placed at (72, 68) inside the original
portrait, so it follows the idle motion
without changing the rest of the character. The eyes and lashes are supplied
by the generated source; the build script only extracts and resizes them.

The blink starts at 3000 ms of the 4800 ms loop. It closes over 50 ms, stays
closed for 100 ms, and reopens over 100 ms. A state change away from `idle`
clears the overlay immediately. Both PNG images remain loaded throughout
playback, with no per-blink file writes or source changes.

## Exact prompt

> Use case: precise-object-edit. Input image is the exact OPEN-EYES reference frame of the Raven chibi mascot, already on transparent alpha. Produce the matching CLOSED-EYES frame for a blink animation. This must be a minimal local edit: change ONLY the girl's two eye openings, irises, pupils, and moving upper eyelashes into softly closed eyelids with delicate dark curved lash lines. Use skin matching the immediate original eyelid/cheek colors to cover the eye openings. Keep the same happy open mouth and original facial expression; do not change the eyebrows, face shape, blush, bangs, nose, or any other facial details. Keep the girl's identity, head tilt, every outline, position, scale, the full-body silhouette, all hair strands, white gloves, clothes, hat, jewelry, tray, raven bird (leave the bird's eye OPEN), gold sparkles, and the original crop EXACTLY unchanged. The closed eyelids should read as a relaxed natural blink with both eyes fully shut, not a wink or sleepy half-open eyes. No amber pupils or white sclera visible in either girl's closed eye. Maintain the identical square canvas, pixel alignment, subject placement and full-body proportions, with genuine transparent alpha background and opaque white clothing. No relighting, repositioning, resizing, restyling, added expression marks, text, watermark, border, background or floor shadow. Output a PNG at the same dimensions as the reference if possible. The purpose is a perfectly registered alternate frame, not a new illustration.
