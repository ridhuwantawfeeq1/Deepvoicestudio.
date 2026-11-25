# Put Deep Voice Studio on your iPhone (no Mac needed)

Two parts: **A.** GitHub builds the app file for free on a cloud Mac. **B.** Sideloadly copies it to your iPhone from Windows.

You need: an iPhone with iOS 16 or newer, a USB cable, a free GitHub account, and your Apple ID.

---

## A. Build the app file (.ipa) on GitHub

1. Make a free account at **github.com/signup**.
2. Click **+** (top right) → **New repository**.
   - Name: `DeepVoiceStudio`
   - Choose **Public**. Mac build minutes are free for public projects. Private also works but has a monthly limit.
   - Click **Create repository**.
3. On the next page, click the **uploading an existing file** link.
4. In File Explorer, open the `DeepVoiceStudio-iOS` folder. Select **everything inside it**, including the `.github` folder, and drag it all onto the GitHub page. Wait for the upload, then click **Commit changes**.
5. Open the **Actions** tab. A build called **Build iPhone app** starts by itself and takes about 5–10 minutes.
   - If GitHub asks you to enable workflows, click the green button. Then click **Build iPhone app** → **Run workflow**.
6. When it shows a green ✓, click that run. Scroll to **Artifacts** and download **DeepVoiceStudio-ipa**. Unzip it to get `DeepVoiceStudio.ipa`.
   - If it shows a red ✗, click the failed step, copy the red error text and send it to Claude to fix.

## B. Install it on your iPhone with Sideloadly (Windows)

1. Install **iTunes** and **iCloud** from apple.com. Use Apple's website downloads, not the Microsoft Store versions; Sideloadly needs these.
2. Download and install **Sideloadly** from **sideloadly.io**. It's a free third-party tool many people use for this.
3. Plug the iPhone into the PC, unlock it and tap **Trust**.
4. Open Sideloadly and drag `DeepVoiceStudio.ipa` into it. Type your **Apple ID** email and click **Start**. Enter your Apple ID password when Sideloadly asks; it goes to Apple to sign the app.
   - Tip: you can use a second Apple ID made just for this.
5. On the iPhone:
   - **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**.
   - **Settings → Privacy & Security → Developer Mode** → **On**, then restart the phone and confirm.
6. Open **Deep Voice Studio** and allow the microphone.

## Good to know
- **Free Apple ID:** the app works for **7 days**. After that, plug in and click Start in Sideloadly again; your files stay. Sideloadly also has an auto-refresh option.
- **Paid Apple Developer account ($99/year):** the app lasts a full year, and you could later publish it on the App Store.
- **Getting files out:** your karaoke tracks and recordings also appear in the **Files** app → **On My iPhone → Deep Voice Studio**. You can also use the share button in the Recordings tab.
- **Songs:** pick them from the Files app. Apple Music songs are copy-protected and can't be used. Save mp3, m4a or wav files to Files first.
