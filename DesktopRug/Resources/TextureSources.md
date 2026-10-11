# Советские текстуры

Дата подготовки: 2026-10-11. Источник: две фотографии, приложенные пользователем к задаче. Текстуры подготовлены встроенным инструментом imagegen, режим precise-object-edit; это адаптации фотографий для ткани, а не историческая атрибуция производства ковров.

- [soviet-red.png](soviet-red.png) — «Советский · Красный»: красное поле, кремовый центральный медальон, плотный орнамент.
- [soviet-floral.png](soviet-floral.png) — «Советский · Цветочный»: тёмно-синее поле, красный бордюр, цветочные ветви.

В обеих текстурах выровнены края и освещение, внешний фон и бахрома исключены. Бахрома и освещение добавляются существующим Metal-рендерером. PNG сохранены в проекте; повторная генерация может дать отличающийся рисунок. Генератор Tools/GenerateRugAssets.swift эти два файла не изменяет.

## Запрос для красного ковра

```text
Use case: precise-object-edit. Asset type: diffuse texture for a native macOS cloth rug. Input image 1 is the edit target, a red Soviet household carpet. Prepare this exact carpet as a clean, flat, rectangular top-down texture. Preserve its recognizable intricate central cream and black medallion, red field, green and cream small floral motifs, dense multiple ornamental borders, original colors and woven pile detail. Straighten only the outer rectangular edges and make the patterned carpet fill the entire landscape image edge to edge, approximately 1.63:1 width to height. Even neutral illumination, no directional shadow, no perspective, no folds, no room, no wall or floor, no external background, no added tassels or fringe, no text. Do not redesign or simplify the motifs. This bitmap will be deformed and lit by a cloth shader, so deliver only the flat full-bleed rug surface including all original ornamental borders.
```

## Запрос для цветочного ковра

```text
Use case: precise-object-edit. Asset type: diffuse texture for a native macOS cloth rug. Input image 1 is the edit target, a Soviet household carpet with a very dark navy field and red floral borders. Prepare this exact carpet as a clean, flat, rectangular top-down texture. Preserve the detailed original composition: very dark navy central field, large red and cream central floral medallion, red side ornaments, winding cream, red, pale blue and olive floral vines, multiple thin patterned borders and broad red outer border. Preserve colors and realistic fine woven wool pile. Remove ONLY the white fringes on the left and right, straighten the edges, normalize uneven lighting. The rectangular rug surface including its original red outer binding must completely fill the landscape image, edge to edge, approximately 1.67:1 width to height. Even neutral illumination; no perspective, no directional shadows, no folds, no background, no wall or floor, no white strips, no tassels or fringe, no text. Do not redesign or simplify the original motifs. This full-bleed bitmap will be deformed and lit by the cloth shader.
```
