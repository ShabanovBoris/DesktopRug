# Soviet rug textures

Prepared on 2026-10-11 from two reference photographs supplied by the project owner. The textures were prepared with the built-in imagegen tool in precise-object-edit mode. They are adaptations for cloth rendering, not a historical attribution of the rugs' manufacturing origin.

- [soviet-red.png](soviet-red.png) — **Soviet · Red**: a red field, cream central medallion, and dense ornamentation.
- [soviet-floral.png](soviet-floral.png) — **Soviet · Floral**: a dark navy field, red border, and floral vines.

Both textures have straightened edges and even lighting, with the external background and fringe removed. The Metal renderer adds fringe and lighting. The PNG files are included in the project; generating them again may produce different patterns. `Tools/GenerateRugAssets.swift` preserves these two files.

## Red rug prompt

```text
Use case: precise-object-edit. Asset type: diffuse texture for a native macOS cloth rug. Input image 1 is the edit target, a red Soviet household carpet. Prepare this exact carpet as a clean, flat, rectangular top-down texture. Preserve its recognizable intricate central cream and black medallion, red field, green and cream small floral motifs, dense multiple ornamental borders, original colors and woven pile detail. Straighten only the outer rectangular edges and make the patterned carpet fill the entire landscape image edge to edge, approximately 1.63:1 width to height. Even neutral illumination, no directional shadow, no perspective, no folds, no room, no wall or floor, no external background, no added tassels or fringe, no text. Do not redesign or simplify the motifs. This bitmap will be deformed and lit by a cloth shader, so deliver only the flat full-bleed rug surface including all original ornamental borders.
```

## Floral rug prompt

```text
Use case: precise-object-edit. Asset type: diffuse texture for a native macOS cloth rug. Input image 1 is the edit target, a Soviet household carpet with a very dark navy field and red floral borders. Prepare this exact carpet as a clean, flat, rectangular top-down texture. Preserve the detailed original composition: very dark navy central field, large red and cream central floral medallion, red side ornaments, winding cream, red, pale blue and olive floral vines, multiple thin patterned borders and broad red outer border. Preserve colors and realistic fine woven wool pile. Remove ONLY the white fringes on the left and right, straighten the edges, normalize uneven lighting. The rectangular rug surface including its original red outer binding must completely fill the landscape image, edge to edge, approximately 1.67:1 width to height. Even neutral illumination; no perspective, no directional shadows, no folds, no background, no wall or floor, no white strips, no tassels or fringe, no text. Do not redesign or simplify the original motifs. This full-bleed bitmap will be deformed and lit by the cloth shader.
```
