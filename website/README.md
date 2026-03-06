# Syncognito Website

This folder contains the landing page and Sparkle appcast for Syncognito.

## Files

- `index.html` - Main landing page
- `styles.css` - Stylesheet
- `appcast.xml` - Sparkle appcast for app updates

## Deployment

Upload these files to `https://apps.schlingel.io/syncognito/`

The appcast expects the following structure:
```
https://apps.schlingel.io/syncognito/
├── index.html
├── styles.css
├── appcast.xml
└── Syncognito-1.0.0.dmg (to be added when building releases)
```

## Sparkle Configuration

When building a new release:

1. Generate the EdDSA key pair using Sparkle's `generate_keys` tool
2. Add the public key to `Syncognito/Info.plist` as `SUPublicEDKey`
3. Sign the DMG using `sign_update` tool
4. Update `appcast.xml` with:
   - New version number
   - Release notes
   - Signed enclosure URL
   - File size

For more information, see [Sparkle's documentation](https://sparkle-project.org/documentation/).
