# Manual tests with real apps (optional)

The side-effect lab ([VALIDATION.md](VALIDATION.md)) uses simulators and Chrome with a
throwaway profile, never personal accounts. These steps check the same effects on real
chat and media apps. Use **throwaway accounts** (a free Slack workspace you create for
this, a free Spotify account), not your work or personal ones. Nothing here is needed
to use iClear; Slack and Spotify are never paused by default.

Before you start: `iclear status` shows the mode. Steps 1-3 only observe; steps 4-7
pause an app on purpose with `iclear freeze <app>` (Active mode is not needed for a
direct request). `iclear thaw --all` or Control-Option-Command-T resumes everything.

## Chat (Slack with a throwaway workspace)

1. `iclear compat Slack` says COMM, Tier S, and explains the wake-window option.
2. With Slack idle in the background for 30 minutes under memory pressure, `iclear
   explain Slack` lists `SKIP_TIER_S`. Pass: Slack is never paused.
3. Start a huddle or call in Slack. `iclear explain Slack` lists the microphone.
4. Hide Slack (Command-H), then `iclear freeze Slack`. From a second device or the web,
   send yourself 3 messages over 2 minutes. `iclear thaw Slack`.
   Record: did Slack show the messages, and how long after the resume? Did it show a
   "reconnecting" banner? Did any notification arrive while it was paused (expected: no)?
5. Repeat step 4 with a 15-minute pause. Record the same, plus whether Slack needed a
   reload.
6. Import the wake-window pack: `iclear config import packaging/rules/chat-wake-windows.json`,
   switch to Active mode for the test, leave Slack hidden and idle for 20 minutes under
   memory pressure, and send yourself a message every few minutes. Record how late each
   one appeared. Undo with `iclear config deny com.tinyspeck.slackmacgap` or by removing
   the keys from `config.json`, and switch back to Observe mode.

## Media (Spotify with a throwaway account)

7. Play a song. `iclear freeze Spotify` must refuse with `SKIP_AUDIO_ACTIVE` (a direct
   request skips the tier check, never the audio check).
8. Pause the song. Within 10 minutes, `iclear explain Spotify` lists `SKIP_AUDIO_RECENT`.
9. After 10 minutes, hide Spotify and `iclear freeze Spotify` (a direct request is
   allowed). Press the play/pause media key, then try Control Center's Now Playing.
   Record: does anything happen? Does macOS start Music instead? Then `iclear thaw
   Spotify` and press play again. Record whether playback works.
10. While Spotify is paused, open Force Quit (Option-Command-Esc). Record whether it
    shows "(Not Responding)" next to Spotify. Do not force-quit it; resume it.

## What to send back

The step number, macOS version, app version, and what you saw. `iclear doctor
--report` adds the Mac model without personal data.
