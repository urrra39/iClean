# Manual tests

Things the automated suite cannot do on its own. Each item names what to check and
what counts as a pass. Results go into [VALIDATION.md](VALIDATION.md) with the date.

## Power and session events

1. **Shutdown while something is stashed.** `iclear stash test`, then Apple menu > Shut
   Down. Pass: shutdown completes without "app is not responding" dialogs; after
   restart, `iclear stash list` says the stash was dropped because of the restart.
2. **Logout while something is frozen.** Same with Log Out. Pass: logout completes.
3. **Sleep and wake with a stash.** Stash, close the lid for at least 5 minutes, open
   it. Pass: the stash is still listed; `iclear pop` brings every app back with its
   windows.
4. **Fast user switching.** Switch to another user and back while something is
   frozen. Pass: nothing stays frozen longer than its normal limit; no errors in
   `iclear status`.
5. **Black Box after an unclean restart (v1.1, H4).** With the Panic Brake installed
   (`iclear brake observe`), hold the power button until the Mac turns off, then start
   it. Pass: the menu shows the unclean-restart notice and `iclear blackbox` prints the
   saved timeline (or says it was empty because the Mac was healthy). Then restart
   normally from the Apple menu. Pass: no notice appears.

## Other hardware and systems

5. **Intel Mac.** Run `iclear selftest --report` and paste the block into a
   compatibility issue.
6. **macOS 13 and 14.** Same as 5.
7. **8 GB Mac.** Same as 5, plus one day in Observe mode and `iclear stats`.

## Permissions

8. **Revoke Accessibility while running.** Pass: `iclear status` and `iclear doctor`
   report it; nothing else breaks; thaw-latency measurement shows "not measured".
