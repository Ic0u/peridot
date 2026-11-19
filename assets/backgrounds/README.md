# Backgrounds

Files in this folder show up in **Settings → Interface → Background** in the hub.

1. Drop the file in this folder (`assets/backgrounds/`): a `.png` / `.jpg` image or a `.webm` video (Roblox can't play `.mp4`).
2. Add it to `backgrounds.json` as `"Name in the dropdown": "file name"`:

```json
{
    "Peridot Waves": "waves.webm",
    "Night Sky": "night.png"
}
```

A value can also be a full `https://` link or an `rbxassetid://` id instead of a file in this folder.
The hub caches each download by file name, so to replace a background, give the new file a new name.

The preinstalled themes (**Interface Settings → Theme → Preinstalled Themes**) each pair with one of these files by name,
so keep the file names as they are. A theme downloads its picture from here the first time it is picked.
