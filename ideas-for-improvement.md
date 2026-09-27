# QIX - Ideas for Improvement (Learnings from Legacy Web Version)

This document gathers all player-facing features, mechanics, and design touches from the legacy web prototype that are not yet in our native LÖVE 2D handheld/desktop build. 

Before removing the legacy files, these ideas are documented in simple, user-focused terms so we can implement them in future updates.

---

## 1. Difficulty Presets (Choose Your Play Style)

In the web version, players could choose between three distinct game feelings instead of one fixed challenge:

| Mode | Who it's for | Gameplay Tweaks |
| :--- | :--- | :--- |
| **Beginner / Casual** | Relaxing exploration & enjoying the artwork | Starts with **4 lives**, a lower starting goal (**55%** instead of 75%), slower enemies, a generous **3.5-second shield**, and a slow, forgiving fuse. |
| **Arcade (Default)** | Authentic 1981 arcade challenge | **3 lives**, classic 65%–75% targets, standard enemy speed, authentic fuse timing. |
| **Master / Hardcore** | Arcade veterans seeking high tension | Starts with only **2 lives**, high claim goals (**70%–85%**), aggressive enemies, and a rapid, ruthless fuse. |

> **User Experience Benefit:** Players on handhelds like the R36S can choose a chill session just to reveal photos, or ramp up the difficulty for a heart-pounding arcade session.

---

## 2. Arcade Cabinet Visual Themes (Phosphor Colors)

The web version allowed players to toggle the entire cabinet color palette on the fly from the Pause Menu:

1. **Neon Classic (Current):** Electric Cyan borders, Hot Pink / Magenta Qix ribbon, and deep midnight background.
2. **Amber CRT Terminal:** Warm 1980s amber monochrome glow (warm orange borders, golden slow cuts, amber sparx). Very easy on the eyes during nighttime handheld play.
3. **Matrix Green Phosphor:** High-contrast retro hacker / green phosphor monitor look (lime green borders, emerald scanlines, neon green accents).

> **User Experience Benefit:** Adds instant nostalgia and variety; players can customize the mood of their handheld screen.

---

## 3. Achievements & Badges (7 Unlockable Medals)

The legacy version tracked 7 satisfying gameplay milestones with on-screen popups ("Achievement Unlocked!") and a dedicated Badges gallery:

- 🔰 **First Contact:** Clear your first round and uncover the hidden art.
- ⚡ **Deep Cut:** Claim 20% or more of the screen in a single daring slow-draw slice.
- ⚔️ **Divide & Conquer:** Trap and split the dual Qixes into separate compartments on Level 3+.
- 💯 **Century Club:** Score 100,000+ points in a single run.
- 👑 **Master Artist:** Uncover 90% or more of the screen in any single round (near perfection!).
- 🛡️ **Veteran Survivor:** Reach Level 5.
- 🎨 **Art Connoisseur:** Successfully uncover 5 different background artworks.

> **User Experience Benefit:** Gives players long-term goals and replay value beyond just chasing high scores.

---

## 4. Top-5 Arcade Leaderboard (Enter Your 3 Initials)

In classic arcade fashion, when a player achieved a top score:
- An arcade name-entry screen let them enter their **3-letter initials** (`AAA`, `LDK`, etc.) using the D-Pad.
- A **Top 5 Hall of Fame** leaderboard displayed rank medals (🥇, 🥈, 🥉), scores, dates, and initials.
- Saved permanently to disk.

> **User Experience Benefit:** Handheld consoles are often passed between friends or family; local leaderboards create fun competitive rivalries.

---

## 5. The Classic "Split-Qix" Score Multiplier (Level 3+)

On Level 3 and above, two independent Qixes roam the field:
- **The Secret Arcade Rule:** If you draw a line right between the two Qixes, trapping Qix #1 on the left and Qix #2 on the right, the game immediately clears the round and awards a **permanent Score Multiplier** (2X, 3X, up to 9X) for all future points in that run!
- Currently in LÖVE, Level 3 spawns 2 Qixes, but trapping them only captures the smaller side without activating the classic score multiplier.

> **User Experience Benefit:** Introduces the most iconic high-risk, high-reward strategy in original QIX history.

---

## 6. Ambient Qix Soundscape (Arcade Drone & Hum)

In addition to border ticks and capture sounds, the web version had:
- **The Qix Hum:** A subtle, deep, oscillating synthesizer drone that pitched up and down depending on how fast and close the Qix was moving.
- **Sparx Mutation Siren:** A brief, urgent alarm siren 5 seconds before Sparx mutate into Super Sparx, warning the player to prepare.

> **User Experience Benefit:** Increases tension through audio feedback—you can *hear* the Qix getting restless even when your eyes are focused on your player marker.

---

## 7. Interactive Help & Rules Guide (In-Game)

A clean, illustrated guide accessible from the Title or Pause Menu that quickly explains:
- The difference between Slow Draw (2X double points, higher risk) and Fast Draw (1X points).
- How the Fuse ignites if you hesitate mid-cut.
- How Sparx patrol the borders and how Super Sparx hunt you.
- Goal percentages and bonus thresholds.

> **User Experience Benefit:** Friendly for newcomers picking up the R36S console who have never played the original 1981 arcade cabinet.

---

## Priority Recommendation for Next Additions

1. **Difficulty Presets** (Casual / Arcade / Master) — Easiest to implement and highest immediate gameplay value.
2. **Top-5 Leaderboard with 3 Initials** — Essential arcade feel on retro handhelds.
3. **Split-Qix Multiplier** — Authentic arcade scoring depth.
4. **Color Themes** (Amber & Matrix) — Visual polish.
