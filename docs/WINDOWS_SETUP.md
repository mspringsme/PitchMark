# Windows Setup for PitchMark Contributors

This guide is for helping with the PitchMark website on a Windows computer.

What works well on Windows:
- Static website edits in `public/`
- Firebase Functions edits in `functions/src/`
- Local Firebase emulators for hosting, functions, and Firestore

What still needs a Mac:
- The iOS app in `PitchMark/`
- Anything that requires Xcode or iOS signing

## What to install

1. Git for Windows.
2. Node.js 20 LTS.
3. Firebase CLI:

```powershell
npm install -g firebase-tools
```

4. VS Code or another editor you like.

## One-time setup

1. Clone the repo on the Windows machine.
2. Open a PowerShell or Windows Terminal window in the project folder.
3. Install the Firebase Functions dependencies:

```powershell
cd functions
npm install
```

4. Sign in to Firebase:

```powershell
firebase login
```

5. The repo is already linked to the Firebase project `pitchmark-fb9f8` in `.firebaserc`.

## Run the site locally

From the project root:

```powershell
firebase emulators:start --only hosting,functions,firestore
```

Then open:

```text
http://127.0.0.1:5000
```

## Where to edit

- Main website pages: `public/index.html`, `public/styles.css`, `public/privacy.html`, `public/terms.html`, `public/support.html`
- Checkout success/cancel pages: `public/stripe-success.html`, `public/stripe-cancel.html`
- Static assets: `public/assets/`
- Deployed Firebase Functions: `functions/src/index.ts`

If you edit the functions code:

1. Go into the `functions/` folder.
2. Rebuild the TypeScript:

```powershell
npm run build
```

3. Restart the emulator or deploy again.

## Deploying changes

- Website only:

```powershell
firebase deploy --only hosting
```

- Functions only:

```powershell
cd functions
npm run build
cd ..
firebase deploy --only functions
```

## Environment files

If checkout or other backend features need Stripe values, copy `functions/.env.example` to `functions/.env` and fill in real values locally.

Do not commit real secrets.

## Common Windows tips

- Use PowerShell or Windows Terminal for the commands above.
- If `firebase` is not recognized, reopen the terminal after installing the CLI.
- If the Firestore emulator mentions Java when you start it, install a current JDK and try again.
- If you only want to help with text, layout, or images, you can stay entirely in `public/` and ignore the iOS app folder.
