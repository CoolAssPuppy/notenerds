# App Store metadata

This file is the English (U.S.) source for the Note Nerds App Store listing. The local release command reads the second-level sections below and overwrites the matching App Store Connect fields.

Preview changes:

```sh
./scripts/ship.py metadata --version 1.0.0
```

Upload and verify them:

```sh
./scripts/ship.py metadata --version 1.0.0 --upload
```

## Locale

en-US

## Name

Note Nerds

## Subtitle

Open it and start writing

## Promotional text

Open Note Nerds and start writing. A calm canvas, familiar paper, and simple tools keep your thoughts moving without setup, clutter, or busywork.

## Description

Open a notebook and start writing.

Note Nerds keeps the page clear and the tools close. Write down a thought before it slips away. Sketch the shape of an idea. Type when words come faster that way. The app has no ads, feeds, or setup screens competing for your attention.

A PAGE THAT STAYS SIMPLE

Write by hand with Apple Pencil, type, sketch, or move between them on the same canvas. Choose blank, cream, grid, dot, legal, daily planner, or weekly planner paper. Pick a pen, width, and color, then get back to the thought.

The canvas gives you room without making you manage it. Layers, shapes, and selection tools are ready when you need them.

FIND IT WHEN YOU NEED IT

Keep notebooks in folders and mark the important ones as favorites. Search typed text and handwriting when you need to return to an old thought.

BRING IN WHAT MATTERS

Add PDFs and images to a page. Export your work as a PDF, PNG, or editable Note Nerds file. Private iCloud sync keeps your notebooks available across your Apple devices. Optional Notion sync sends restorable copies directly to the workspace you choose.

PRIVACY WITHOUT EXTRA WORK

Note Nerds has no ads, analytics SDK, or tracking. Your notes stay on your device and in your private iCloud account when sync is available.

## Keywords

notes,handwriting,notebook,pencil,canvas,journal,paper,planner,sketch,drawing,focus,ideas

## First update release notes

Apple does not show “What’s New” for an app’s first release. Use this text for the first update:

Note Nerds now includes daily and weekly planner paper, more reliable writing and selection, and faster access to Writing, stroke width, ink color, Eraser, and Lasso from the main toolbar.

## Support URL

https://github.com/CoolAssPuppy/notenerds/issues

## Marketing URL

https://github.com/CoolAssPuppy/notenerds

## Privacy policy URL

https://github.com/CoolAssPuppy/notenerds/blob/main/docs/privacy-policy.md

## Copyright

2026 Prashant Sridharan

## Messaging direction

Note Nerds is about getting a thought onto the page with as little effort as possible. Marketing should lead with opening a notebook and writing. Paper, tools, folders, search, sync, and export support that promise and should never become the main message.

Keep the language calm, short, and plain. Describe familiar writing before advanced editing. Avoid long feature inventories, technical architecture, productivity claims, and comparisons with other products.

## App information outside the upload command

| Field | Value |
| --- | --- |
| Primary category | Productivity |
| Secondary category | Graphics & Design |
| SKU | `NOTENERDS-IOS-001` |
| Bundle ID | `com.strategicnerds.notenerds` |
| Primary language | English (U.S.) |

## Screenshot plan

Capture the real shipping app with one coherent sample notebook across the set. Provide the required iPhone and iPad sizes shown in App Store Connect.

| Order | Caption | Screen to show |
| --- | --- | --- |
| 1 | A notebook made for thinking | Finished handwritten and typed canvas with the toolbar visible |
| 2 | Write naturally with Apple Pencil | Ink, highlighter, and a recognized shape on iPad |
| 3 | Choose the paper that fits | Paper gallery with planner, grid, dot, legal, and blank paper |
| 4 | Keep every notebook in its place | Library with folders and notebook previews |
| 5 | Type directly on the page | Inline text editor active beside handwriting |
| 6 | Find typed and handwritten notes | Search results for a useful phrase |
| 7 | Work with layers | Canvas with the layers menu open |
| 8 | Bring in PDFs and images | Imported PDF or image placed on a canvas |
| 9 | Share useful files | Export menu showing PDF, PNG, and editable notebook options |
| 10 | Your notes stay yours | Settings and library view with a short privacy caption |

Screenshot rules:

- Show the real app and real interactions.
- Keep marketing captions away from interface controls.
- Avoid claims about features that are absent from the submitted build.
- Do not show competitor names, copyrighted documents, personal data, or placeholder content.

## App privacy answers

Use the conservative disclosure for the optional Notion connection:

- Select “Yes, we collect data from this app.”
- User Content: Other User Content, linked to the user, used for App Functionality.
- Identifiers: User ID, linked to the user, used for App Functionality. This covers Notion workspace and bot identifiers.
- Tracking: No.
- Third-party advertising: No.
- Developer advertising or marketing data collection: No.
- Analytics data collection: No.
- Data broker sharing: No.

Notes and drawings are processed locally unless the user enables Notion. Private CloudKit storage is provided by Apple. Notion receives the notebooks selected for sync and stores them in the user’s workspace. Note Nerds may also add a notebook-page link to an active Notion AI meeting note. The app contains no advertising, analytics, crash-reporting, or developer account SDK.

## Age rating guidance

Use the lowest age rating produced by the current questionnaire.

- Objectionable content categories: None.
- Gambling, contests, and loot boxes: No.
- Unrestricted web access: No.
- User communication or public sharing inside the app: No.
- Parental controls: Not applicable.
- Made for Kids: No.

Users can write private free-form notes. The app has no public content feed or communication system.

## Content rights

Select the answer stating that the app does not contain, show, or access third-party content supplied by the developer. Users may import their own PDFs and images and remain responsible for those files.

## Encryption and export compliance

The app uses Apple system encryption through iCloud and standard network security. It does not implement non-exempt or proprietary encryption. `ITSAppUsesNonExemptEncryption` is set to `false` in the generated Info.plist.

## App Review information

### Sign-in required

No.

### Demo account

None required.

### Review notes

Note Nerds is a local-first notebook and drawing app for iPhone and iPad. No account or subscription is required. Notion connection is optional and can be reviewed without connecting an account.

Suggested review path:

1. Tap the new-notebook button in the upper-right corner of My Notebooks.
2. Choose a paper style and create the notebook.
3. Select a writing tool, handwrite a clear word that does not appear elsewhere in the notebook, and pause briefly while recognition runs on the device.
4. Select the text tool, tap the canvas, type a different phrase, and press Return.
5. Return to the library, create a folder with the plus button beside Folders, and drag the notebook into it.
6. Tap Search and search for the handwritten word, then search for the typed phrase. Each result should open the notebook.
7. Open the notebook and use the share menu to export a PDF.
8. Optional: open App settings, connect Notion, choose an accessible page, then use Sync now.

iCloud sync uses the user’s private CloudKit database and may require an iCloud-enabled test device. Notebook, drawing, text, organization, import, and export features work locally.

Notion OAuth returns to `http://localhost:53117/oauth/notion` through a listener bound to the device. Note Nerds sends notebook data directly to Notion and does not use a developer server.

Apple Pencil improves drawing on iPad. Finger drawing can be enabled in Settings.

### Contact fields

Enter the current App Review contact name, phone number, and private email address directly in App Store Connect. Do not place personal review contact details in the repository.

## Pricing and availability

The submitted binary contains no purchase or subscription flow. Choose free or paid upfront before submission. Do not create paid features, subscriptions, or promotional purchase copy for version 1.0.0.

Recommended first-release availability is every country or region where the developer account can distribute the app, with manual release after approval.

## App Store Connect completion checklist

- Confirm the name is available.
- Select Productivity and Graphics & Design categories.
- Set pricing and availability.
- Complete the age-rating questionnaire.
- Publish App Privacy answers.
- Upload required iPhone and iPad screenshots.
- Enter App Review contact fields.
- Confirm content rights and export compliance.
- Attach the processed 1.0.0 build.
- Keep release mode manual for the first submission.
- Submit after every required field shows complete.
