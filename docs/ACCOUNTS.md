# Accounts, stats and (later) the cloud

Everything lives on the device in `user://accounts.json` (on Windows `%APPDATA%\\Godot\\app_userdata\\Storm Island\\`,
on Android the app's private storage). `scripts/Accounts.gd` is an autoload.

* **Guest profile** always exists, so progress is never lost. **Create account** (email + password + display name) moves the
  guest's stats, Locker and name into the new account; **sign out** returns to a fresh guest.
* Passwords are never stored: each account keeps a random salt and a 4000-round salted SHA-256 hash. The last signed-in
  account stays signed in.
* Each profile holds the display name, Locker loadout, starting sprite, XP/level and stats (matches, wins, top 3, eliminations,
  deaths, damage, headshots, chests, pieces built, time played, best eliminations, best placement, longest survival).
  `World._record_match()` hands the finished match to `Accounts.record_match()`.
* The lobby card (level, stats), the **PROFILE** tab (full stats, create account, sign in / out) and the Settings name field
  all read and write the active profile.

## Adding a cloud backend later (Convex, Google sign-in, ...)

Nothing in the game needs a server, so none is required. If you want sync across devices or leaderboards:

1. Create the backend (for Convex: `npx convex dev`, a `profiles` table keyed by email / user id).
2. Connect to `Accounts.saved` (fires after every write) and push `Accounts.export_profile()`; on sign-in pull and call
   `Accounts.import_profile(dict)`.
3. For Google OAuth, replace the email + password sign-in in `Menu.profile_submit()` with the OAuth result and keep the rest:
   an account is just a key plus a profile dictionary.

Desktop OAuth needs a Google Cloud OAuth client ID and a loopback redirect; Android uses the system browser or Google Play Games.
Passwords stay local; if you add a server, never send the plain password and hash it server-side.
