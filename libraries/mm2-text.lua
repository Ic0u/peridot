-- Plain-English layout and wording for the Murder Mystery 2 window (games/142823291.lua).
-- The script names its sections and controls in developer terms; this file says where each
-- one goes and what to call it. Nothing here changes what a control does.
--
-- sections: section key => page, tab, title, intro
--   (a key is the script's section name in lower case with symbols removed)
-- controls: one per line, columns separated by " | ":
--   section key or *  |  [Type:] original label  |  new title ("-" hides it)  |  help  |  options
--   options: route=Page/Tab/Section (put it in another section)  btn=Text (button label)
--   a leading "~" on the label makes it a Lua pattern; %1 in the title is its first capture
-- values: dropdown values shown in plain words, keyed by the script's own label for the dropdown
--   (the script still gets its own value back)
-- words: phrases replaced in anything not listed above, and in notifications

local Text = {
    pages = { "Gun", "Knife", "Player", "See", "Fun", "Emotes", "Teleport", "Extras" },

    tabs = {
        Gun = { "Aim", "Trails", "Auto Shoot", "Tuning" },
        Knife = { "Aim", "Kill Tools", "Tuning" },
        Player = { "Movement", "Protect", "Game", "Looks" },
        See = { "Players", "Items", "View" },
        Fun = { "Fling", "Lists", "Options", "Bomb Jump", "Troll" },
        Emotes = { "Animations", "Browser" },
        Teleport = { "Places" },
        Extras = { "Aim Lock", "Cursor", "Speed", "Items", "Panels" },
    },

    fallback = { page = "Extras", tab = "Panels" },

    sections = {
        ["silent aim"] = { "Gun", "Aim", "Aim Assist", "Bends your gun shots toward the player you pick. Hold the gun and shoot as normal." },
        ["gun"] = { "Gun", "Aim", "Through Walls", "What happens when a wall is between you and your target." },
        ["noir auto prediction profile"] = { "Gun", "Tuning", "Auto Lag Adjust", "Keeps your aim accurate when your connection is slow. It adjusts itself while you play." },
        ["pistol prediction"] = { "Gun", "Tuning", "Gun Aim Lead", "How far ahead your gun shots aim at moving players. Most people never need to change these." },
        ["world gun"] = { "Gun", "Auto Shoot", "Grab The Gun", "Helps you pick up the Sheriff's gun when it drops." },

        ["knife silent aim"] = { "Knife", "Aim", "Knife Aim Assist", "Bends your knife throws toward the nearest player." },
        ["pistol noir config"] = { "Gun", "Tuning", "Gun Saved Setups", "Save the numbers above as a setup you can load later." },
        ["knife noir config"] = { "Knife", "Tuning", "Knife Saved Setups", "Save the numbers above as a setup you can load later." },
        ["knife prediction"] = { "Knife", "Tuning", "Knife Aim Lead", "How far ahead your knife throws aim at moving players. Most people never need to change these." },

        ["main self mods"] = { "Player", "Movement", "Speed And Jumping", "Change how fast you walk and how high you jump." },
        ["main universal"] = { "Player", "Movement", "Speed And Jumping", "" },
        ["main fly"] = { "Player", "Movement", "Fly", "Fly around the map by pointing your camera where you want to go." },
        ["main noclip"] = { "Player", "Movement", "Walk Through Walls", "Walk straight through walls and objects." },
        ["main speed glitch"] = { "Player", "Movement", "Speed Boost", "Adds a floating button that makes you move much faster for as long as it is on." },
        ["pm wallhop"] = { "Player", "Movement", "Wall Jump", "Jump off walls to climb or boost yourself." },
        ["main invisible"] = { "Player", "Protect", "Invisible", "Other players cannot see you while this is on." },
        ["misc desync"] = { "Player", "Protect", "Fake Position", "Other players see you standing where you turned this on while you move around freely." },
        ["main server"] = { "Player", "Game", "Round Info", "Shows who the murderer and sheriff are, and how long the round has left." },
        ["main fun client"] = { "Player", "Looks", "Avatar Looks", "Changes how your own character looks. Only you see it." },

        ["visual cham"] = { "See", "Players", "Solid Color Players", "Fills players with a solid color so you can spot them. Choose who below." },
        ["visual esp"] = { "See", "Players", "Name Tags", "Shows a name tag above players. Choose who below." },
        ["visual outline"] = { "See", "Players", "Outlines", "Draws an outline around players. Choose who below." },
        ["visual highlight"] = { "See", "Players", "Highlights", "Makes players glow so they stand out. Choose who below." },
        ["visual tracer"] = { "See", "Players", "Lines To Players", "Draws a line from you to each player. Choose who below." },
        ["visual esp box"] = { "See", "Players", "Boxes Around Players", "Draws a box around players. Choose who below." },
        ["visual esp avatar"] = { "See", "Players", "Player Pictures", "Shows each player's picture over them. Choose who below." },
        ["visual esp fire"] = { "See", "Players", "Fire On Players", "Sets a fire effect on players so they are easy to spot. Choose who below." },
        ["visual by object"] = { "See", "Items", "Items On The Map", "Marks useful items so you can find them." },
        ["main xray"] = { "See", "View", "See Through Walls", "Makes walls and objects see-through. Only you see this." },
        ["main hitbox expander"] = { "See", "View", "Bigger Hit Areas", "Makes other players easier to hit by making their hit area bigger." },
        ["main custom skybox"] = { "See", "View", "Sky", "Change how the sky looks and what time of day it is. Only you see this." },

        ["fling"] = { "Fun", "Fling", "Fling Players", "Throws players across the map. Pick who, then press a button." },
        ["auto"] = { "Fun", "Fling", "Auto Fling", "Flings by itself without you pressing anything." },
        ["lists"] = { "Fun", "Lists", "Player Lists", "Choose who gets flung again and again, and who is protected." },
        ["tuning"] = { "Fun", "Options", "Fling Settings", "How strong, how long and how often flings happen." },
        ["binds"] = { "Fun", "Options", "On-Screen Buttons", "Round buttons on your screen for each fling." },
        ["keys"] = { "Fun", "Options", "Keyboard Keys", "Keys that start each fling." },
        ["bomb jump"] = { "Fun", "Bomb Jump", "Bomb Jump", "Use a bomb to launch yourself high in the air." },
        ["gold bomb jump"] = { "Fun", "Bomb Jump", "Gold Bomb Jump", "The same trick with the Gold Bomb." },
        ["about"] = { "Fun", "Bomb Jump", "Sound And Credits", "" },
        ["troll backshots"] = { "Fun", "Troll", "Backshots", "A joke move: shuffles you back and forth behind a player." },
        ["troll jerk r15"] = { "Fun", "Troll", "Jerk", "A joke animation. Needs the newer body type (R15)." },
        ["troll bang"] = { "Fun", "Troll", "Bang", "A joke move: sticks you to a player you pick with a looping animation." },

        ["fe animations"] = { "Emotes", "Animations", "Custom Animations", "Swap your standing, walking, running, jumping, climbing and falling animations. Other players see them too." },

        ["map teleport"] = { "Teleport", "Places", "Go Somewhere", "Jump to a player, the gun, the map or the lobby." },

        ["misc aimlock"] = { "Extras", "Aim Lock", "Camera Aim Lock", "Keeps your camera pointed at the murderer or a player you pick." },
        ["misc customize cursor"] = { "Extras", "Cursor", "Custom Cursor", "Replaces the crosshair with a picture of your choice." },
        ["misc cursor plus"] = { "Extras", "Cursor", "Spinning Cursor", "Make your cursor spin and change its size." },
        ["misc fps"] = { "Extras", "Speed", "Smoother Game", "Turns down some effects so the game runs smoothly on slower devices. Only you see the change." },
        ["inventory unlimiter v5"] = { "Extras", "Items", "Item Limit", "Lets your inventory show more items than normal. Only you see this." },
        ["main background"] = { "Extras", "Panels", "Panel Backdrop", "A picture behind the extra panels (emote browser, skin changer)." },
    },

    controls = [[
silent aim | Enabled | Aim Assist | Your gun shots go toward the target on their own, even if you aim a little off.
* | Wall Check | Ignore Targets Behind Walls | Only helps against players you could actually hit.
* | Show Shoot Murder Button | Shoot Murderer Button | Puts a button on your screen. Tap it to shoot the murderer.
* | Lock Shoot Murder Button | Lock The Button In Place | Stops the on-screen button from being dragged by accident.
* | Silent Aim Mode | Aim Style | Normal is the standard aim. Alternate uses a different style.
* | Bullet Tracer | - |
* | Bullet Tracers | Show Bullet Trails | A glowing trail follows each shot so you can see where it went. | route=Gun/Trails/Bullet Trails
* | Tracer Method | Trail Type | | route=Gun/Trails/Bullet Trails
* | Tracer Style | Trail Style | Pick how the trail looks. | route=Gun/Trails/Bullet Trails
* | Tracer Color | Trail Color | | route=Gun/Trails/Bullet Trails
* | Tail Color | Trail End Color | | route=Gun/Trails/Bullet Trails
* | Rainbow Tracers | Rainbow Trails | The trail color cycles through the rainbow. | route=Gun/Trails/Bullet Trails
* | Tracer Width | Trail Thickness | | route=Gun/Trails/Bullet Trails
* | Tracer Speed | Trail Speed | | route=Gun/Trails/Bullet Trails
* | Tracer Duration | How Long Trails Last | | route=Gun/Trails/Bullet Trails
* | Impact Effect | Hit Spark | A small burst where the shot lands. | route=Gun/Trails/Shot Effects
* | Muzzle Flash | Gun Flash | A flash at the gun when you shoot. | route=Gun/Trails/Shot Effects
* | Show Other Shots | Show Other Players' Shots | Draws trails for other players' shots too. | route=Gun/Trails/Shot Effects
* | Preview Tracer | Preview The Trail | | route=Gun/Trails/Bullet Trails btn=Preview

noir auto prediction profile | Auto Prediction | Adjust Aim For Lag | Reads your connection delay and keeps your aim ahead of moving players. Turning it off keeps the last values.
* | Adaptive Engine | Let It Adjust Itself | The aim settings change on their own as the game goes on.
* | Lock Config | Keep Current Settings | Stops the settings from changing on their own.
* | Upgrade Mode | Extra Accuracy Mode | Uses a more careful method. It may use a little more of your device.
* | Monitor | Show Connection Delay | Shows a small box with your connection delay.
* | FPS Boost | - | The same switch as Smoother Game on the Extras page.
* | Print Telemetry | - |
* | Noir Auto updates gun prediction using ping. Turning it off stops updates and keeps the last values. | - |
* | FPS Boost is shared with the hub's MISC • FPS control. | - |
* | GUN UTILITIES • native Noir implementation | - |
* | GUN TRIGGER BOT | - |
* | Gun Trigger Bot | Auto Shoot | Shoots by itself when a target is in your sights. | route=Gun/Auto Shoot/Auto Shoot
* | Gun Trigger Bot Wall Check | Don't Auto Shoot Through Walls | | route=Gun/Auto Shoot/Auto Shoot
* | Apply Prediction On Gun Trigger Bot | Aim Ahead When Auto Shooting | Leads moving players when it shoots for you. | route=Gun/Auto Shoot/Auto Shoot

gun | Piercer Bullet | Shoot Through Walls | If a wall is in the way, the shot starts on the other side of it. Use together with Aim Assist.
gun | If a wall is between you and the target, the shot starts on their side of the wall. Turn this on with Silent Aim. | - |

world gun | Enable Auto GG | Auto Grab Dropped Gun | Picks up the gun for you when it drops and you do not have one.
* | Auto GG picks up GunDrop while you do not have a Gun. | - |
* | Grab Gun | Grab The Gun Now | | btn=Grab
* | Gun Aura | Grab Gun From Far Away | Picks up the gun when you are within the range below.
* | Gun Aura Range | Grab Range |
* | Auto Notify Dropped Gun | Tell Me When The Gun Drops | Shows a message when the sheriff's gun is dropped.
* | Gun Pickup Notify | Tell Me When Someone Picks It Up | Shows a message when someone grabs the gun.
* | Enable Grab Gun Bind Button | On-Screen Grab Gun Button | A round button on your screen that grabs the gun.
* | Grab Gun Bind Button Size | Button Size |
* | Round Grab Gun button: drag it to move; its size and position are saved. | - |

knife silent aim | Knife Silent Aim | Knife Aim Assist | Your thrown knives go toward the nearest player.
* | KnifeThrown Aura | Auto Throw At Nearby Players | Throws a knife by itself at anyone within the range below.
* | Knife Throw Aura | Throw Range |
* | Knife Wall Check | Ignore Targets Behind Walls | Only throws at players you could actually hit.
* | Prioritize Sheriff | Go For The Sheriff First | Picks the sheriff before other players.
* | NATIVE KNIFE UTILITIES • equipped Knife only | - |
* | Instant Throw | Instant Throw | Throws as soon as you press, with no wind-up. | route=Knife/Kill Tools/Throwing
* | Fast Throw | Faster Throws | Throws knives quicker than normal. | route=Knife/Kill Tools/Throwing
* | Auto Kill Everyone | Auto Kill Everyone | Keeps throwing at everyone until they are out. | route=Knife/Kill Tools/Kill Players
* | Auto Kill Sheriff | Auto Kill The Sheriff | Keeps throwing at the sheriff until they are out. | route=Knife/Kill Tools/Kill Players
* | Button: Kill Everyone | Kill Everyone Now | | route=Knife/Kill Tools/Kill Players btn=Kill
* | Button: Kill Sheriff | Kill The Sheriff Now | | route=Knife/Kill Tools/Kill Players btn=Kill
* | Enable Kill Sheriff Bindable Button | On-Screen Kill Sheriff Button | A round button on your screen that kills the sheriff. | route=Knife/Kill Tools/Kill Players
* | Dropdown: Kill Player | Player To Kill | | route=Knife/Kill Tools/Kill One Player
* | Button: Kill Player | Kill That Player | | route=Knife/Kill Tools/Kill One Player btn=Kill
* | Refresh Kill Player List | Refresh Player List | | route=Knife/Kill Tools/Kill One Player btn=Refresh

* | Prioritize Your Ping | Account For Your Lag | Takes your own connection delay into account.
* | Predict Jump | Expect Players To Jump | Aims for where a jumping player will be.
* | Predict Lag | Expect Other Players' Lag | Aims for where a lagging player will be.
* | Prediction Max Simulation | Longest Look-Ahead |
* | Prediction Interval | How Often It Updates |
* | Prediction Ping | Your Connection Delay |
* | X Position Offset | Aim Shift: Left Or Right |
* | Y Position Offset | Aim Shift: Up Or Down |
* | Z Position Offset | Aim Shift: Forward Or Back |
* | Horizontal Multiplier | Sideways Lead Strength |
* | Vertical Multiplier | Up And Down Lead Strength |
* | Your Presets | Saved Setups |
* | Preset Name | Setup Name |
* | ~^Save .+ Preset$ | Save Setup | Saves the numbers above under the name you typed. | btn=Save
* | ~^Load .+ Preset$ | Load Setup | Uses the saved setup you picked. | btn=Load

main self mods | Enable WalkSpeed | Change Walking Speed | Turn on to use the speed below.
* | WalkSpeed | Walking Speed |
* | Enable JumpPower | Change Jump Height | Turn on to use the height below.
* | JumpPower | Jump Height |
* | Auto Prestige | Auto Prestige | Prestiges for you as soon as you are able to. | route=Player/Game/Prestige
* | Prestige Now | Prestige Now | | route=Player/Game/Prestige btn=Prestige
main universal | Infinite Jump | Jump In Mid-Air | Lets you keep jumping while in the air.
main fly | Fly | Fly | Turn on, then use your movement keys to fly where your camera points.
* | Enable Fly Bind Button | On-Screen Fly Button | A round button on your screen that turns flying on and off.
* | Fly Bind Button Size | Button Size |
* | Fly Speed | Fly Speed |
main noclip | Noclip | Walk Through Walls | Lets you pass through walls and objects.
* | Enable Noclip Bind Button | On-Screen Button | A round button on your screen that turns this on and off.
* | Noclip Bind Button Size | Button Size |
main speed glitch | Enable Speed Glitch UI | Show Speed Boost Button | A floating button appears. Tap it to turn the boost on or off.
* | Only Work Sideways | Only Boost Sideways | Only speeds you up when moving left or right.
* | Side Speed | Boost Strength |
* | Toggle Size | Button Size |
* | Select Emote | Emote It Uses | The boost works by timing this emote.
* | Custom Emote ID | Your Own Emote Number | Paste the number of an emote to use it instead.
* | Tap the floating button to toggle the glitch; drag to move it. Position is saved and the UI auto-recovers if removed. | - |
pm wallhop | Pm-WallHop Script by @Phemtom (Improved) | Wall jump by Phemtom (improved) | Credit to the original author.
* | Pm-WallHop | - |
* | Toggle: WallHop | Wall Jump | Jump off walls to climb or boost yourself.
* | Button: WallHop | Turn Wall Jump On Or Off | | btn=Switch
* | Дистанция обнаружения | How Close A Wall Must Be |
* | Сила флинга | Jump Strength |
* | Toggle Keybind | Key To Turn It On Or Off |
* | WallHop Jump Key | Wall Jump Key |

main invisible | Invisible | Invisible | Others cannot see you while this is on.
* | Enable Invisible Bind Button | On-Screen Invisible Button | A round button on your screen that turns this on and off.
* | Invisible Bind Button Size | Button Size |
* | Round Invisible button: tap to toggle; drag it to move. Its size and position are saved. | - |
misc desync | Desync | Fake Position | Others see you standing where you turned this on while you move around freely.
* | Enable Desync Bind Button | On-Screen Button | A round button on your screen that turns this on and off.
* | Desync Bind Button Size | Button Size |
* | Enable Desync to save the current position; you can then move locally while its saved position is sent on desync frames. | - |

misc fps | Fps Boost | Smoother Game | Turns down some effects so the game runs smoothly.
* | Less Lag | Less Lag | Removes extra things that slow the game down.
* | No Shadows | No Shadows | Turns shadows off.
* | Optimize Coins | Lighter Coins | Makes coins use less of your device.
* | Auto Remove Chroma Effects | Hide Chroma Glow | Removes the shiny effects from Chroma items.
* | Auto Remove Pets Display | Hide Pets | Hides pets so they do not slow you down.
* | Auto Remove Coins | Hide Coins | Removes coins from your view.
* | Auto Remove Corpses | Hide Dead Bodies | Removes dead bodies from your view.
* | Enable Frame Enhancement | Smoother Frame Rate | Helps the game keep a steady frame rate.
* | Client-side protections | - |
* | Fade | Remove Screen Fade | Hides the dark overlays that block your view. | route=Player/Protect/Protection
* | Trap | Escape Traps | Frees you when you get caught in a trap. | route=Player/Protect/Protection
* | AntiFling | Block Flings From Others | Stops other players from flinging you. | route=Player/Protect/Protection
* | Anti AFK | Stay Online While Idle | Stops the game from kicking you for standing still. | route=Player/Protect/Protection
* | Anti Void | Don't Fall Off The Map | Brings you back if you fall out of the map. | route=Player/Protect/Protection

main server | Show Round Timer | Show Round Timer | Shows how long the round has left.
* | Instant Role Detection | Find Roles Right Away | Works out who the murderer and sheriff are as early as it can.
* | Auto Notify Roles | Tell Me The Roles | Shows a message with the roles when they are known.
* | Show Murderer Chance | Show My Murderer Chance | | btn=Show
* | Refresh Roles | Check Roles Again | | btn=Check
* | Roles are sampled during the 10 second countdown. | Roles are checked during the 10 second countdown before a round. |
main fun client | Permanent Korblox (R15) | Korblox Leg | Gives you the Korblox leg look. Needs the newer body type (R15). It comes back after each respawn.
* | Permanent Headless | Headless Look | Hides your head. It comes back after each respawn.
* | Both looks are reapplied after each respawn. Korblox requires an R15 character. | - |

visual by object | Dropped Gun | Mark The Dropped Gun | Shows where the sheriff's gun is after it drops.
* | Throwing Knives | Mark Flying Knives | Shows knives while they are in the air.
visual* | Everyone | Everyone | Marks every player.
visual* | Murderer Only | Only The Murderer |
visual* | Sheriff Only | Only The Sheriff |
visual* | Hero Only | Only The Hero | The hero is the player who picked up the sheriff's gun.
visual* | Dead Only | Only Dead Players |
main xray | Enable Xray | See Through Walls | Makes walls and objects see-through.
* | Xray Transparency | How See-Through |
* | Local only: nothing is sent to the server. | - |
main hitbox expander | Enable Hitbox Expander | Bigger Hit Areas | Makes other players' hit areas bigger so shots land more easily.
* | Hitbox Size | Hit Area Size |
* | Hitbox Transparency | Hit Area See-Through |
* | Enlarges other players hitboxes locally. | - |
main custom skybox | Skybox Preset | Sky Style |
* | Custom Skybox ID | Your Own Sky Picture Number | Paste the number of a sky picture to use it.
* | Sky Time (hour) | Time Of Day (hour) |

fling | Button: Sheriff | Fling The Sheriff | | btn=Fling
* | Button: Murderer | Fling The Murderer | | btn=Fling
* | Button: Selected | Fling The Chosen Player | | btn=Fling
* | Button: Everyone | Fling Everyone | | btn=Fling
* | Button: Nearest | Fling The Closest Player | | btn=Fling
* | Button: Start (list) | Start Flinging The List | Flings the players on your loop list one after another. | btn=Start
* | Button: Cancel | Stop Flinging | | btn=Stop
* | Button: Touch Fling | Touch Fling | Fling anyone you touch. | btn=Start
* | PlayerDropdown: Fling player | Player To Fling |
* | Toggle: Touch Fling | Touch Fling | Anyone you touch gets flung.
* | Bind Touch Fling | On-Screen Touch Fling Button | A round button on your screen for touch fling.
auto | Toggle: Auto Sheriff | Auto Fling The Sheriff | Flings the sheriff by itself.
* | Auto Murderer | Auto Fling The Murderer | Flings the murderer by itself.
* | Toggle: Loop | Keep Flinging The List | Keeps flinging the players on your loop list.
* | Aura | Fling Anyone Who Comes Close | Flings players that get near you.
* | Click | Fling By Clicking | Click a player to fling them.
lists | PlayerDropdown: Select | Choose A Player |
* | PlayerDropdown: Loop | Add To Loop List | Adds a player to the list that keeps getting flung.
* | Button: Clear loop | Clear Loop List | | btn=Clear
* | PlayerDropdown: Whitelist | Protect A Player | This player will never be flung.
* | PlayerDropdown: Un-whitelist | Stop Protecting A Player |
* | Button: Clear WL | Clear Protected List | | btn=Clear
tuning | Fling Duration | How Long Each Fling Lasts |
* | Fling Power | Fling Strength |
* | Prediction | Aim Ahead |
* | Start Height | Starting Height |
* | Aura Radius | Close Range Distance |
* | Loop Interval | Time Between Loop Flings |
* | Aura Interval | Time Between Close Flings |
* | Target Cooldown | Wait Before Flinging Someone Again |
* | Auto Sheriff Delay | Wait Before Auto Flinging The Sheriff |
* | Auto Murderer Delay | Wait Before Auto Flinging The Murderer |
* | Role Cache TTL | How Long Roles Are Remembered |
* | Auto Return | Go Back To Where You Started | Returns you to your starting spot after a fling.
* | Notifications | Show Messages |
* | SFX | Mute Sounds |
binds | ~^Bind (.+)$ | On-Screen Button: %1 | A round button on your screen for this fling.
* | Slider: Bind Size | Button Size |
* | Button: Reset bind layout | Reset Button Positions | | btn=Reset
* | Button: Panic | Stop Everything | Stops every fling right away. | btn=Stop
keys | ~^Key (.+)$ | Key: %1 | Pick a key for this fling.
* | Button: Clear keys | Clear All Keys | | btn=Clear

bomb jump | Show Bomb Jump Button | On-Screen Bomb Jump Button | A round button on your screen that does the bomb jump.
* | Choose Bomb Type | Bomb |
* | Bomb Usage Mode | How To Use It |
* | No GUI Timer ( Not Recommended ) | Hide The Cooldown Timer | Not recommended: you will not see when you can jump again.
* | Bomb Jump Keybind | Bomb Jump Key |
* | Bomb Jump GUI Size | Button Size |
* | Bomb Jump ported from Better ODH: jump-equip-use-jump sequence with cooldown guard. | - |
* | Auto Clutch Firefly | Auto Firefly Save | Moves you above a firefly and jumps off it at the last moment.
* | Firefly Cooldown (s) | Wait Between Tries |
* | Equip Fireflies Now | Take Out Fireflies Now | | btn=Take out
* | SNPWARE logic: watches for the Firefly part and teleports you above it, then jumps. | - |
* | ~^(.+) Options$ | - |
* | ~^Enable Auto (.+)$ | Auto %1 | Does the whole jump for you: jump, take out the bomb, use it, jump again.
* | ~^Auto%-Get (.+)$ | Pick Up A %1 Automatically |
* | ~^Enable (.+) Bind Button$ | On-Screen %1 Button | A round button on your screen.
* | ~^(.+) Bind Button Size$ | %1 Button Size |
* | ~^(.+) Keybind$ | %1 Key |
about | Bomb Jump+ | - |
* | Mute Button SFX | Mute Button Sounds | Silences the click sounds of the on-screen buttons.

troll backshots | Show Backshots Button | On-Screen Backshots Button | A round button on your screen that starts this.
* | Backshots Keybind | Backshots Key |
* | Backshots Speed | Speed |
* | Backshots Distance | Distance |
* | Backshots GUI Size | Button Size |
* | Backshots ported from Better ODH: camera-locked backward shuffle troll. | - |
troll jerk r15 | Show Jerk Button | On-Screen Jerk Button | A round button on your screen that starts this.
* | Jerk Button Size | Button Size |
* | Enable Jerk R15 | Jerk | Plays the joke animation. Needs the newer body type (R15).
* | Jerk Speed (higher = faster) | Speed |
* | Jerk R15 Keybind | Jerk Key |
* | Requires an R15 rig. Reapplies if the track stops; turns off on respawn. | - |
troll bang | Bang Target | Player To Follow |
* | Refresh Player List | Refresh Player List | | btn=Refresh
* | Bang Player | Bang | Sticks you to the chosen player. It stops if they leave or you respawn.
* | Bang Speed | Speed |
* | Bang Keybind | Bang Key |
* | Pick a target, hit Refresh if the list is stale, then enable. Stops automatically if the target leaves or you respawn. | - |

fe animations | Loading settings... | - |
* | Saved settings | - |
* | Enable FE Anims | Use Custom Animations | Turn on to use the animations you picked below. Your choices are saved.
* | All Animations | Animation Pack For Everything | Sets every animation below at once.
* | Idle Animation | Standing Animation |
* | Walk Animation | Walking Animation |
* | Run Animation | Running Animation |
* | Jump Animation | Jumping Animation |
* | Climb Animation | Climbing Animation |
* | Fall Animation | Falling Animation |
* | Full animation reset | - |
* | Reapply / Retry | Apply Again | Briefly stops your current animations, then applies the ones you picked. | btn=Apply

map teleport | Teleport Target | Who To Go To | Murderer, Sheriff or a random player.
* | Teleport Player | Choose A Player |
* | Teleport Distance | How Far Away You Land |
* | Teleport to Selected Player | Go To The Chosen Player | | btn=Go
* | Teleport to Role Target | Go To The Murderer Or Sheriff | | btn=Go
* | Teleport to Gun | Go To The Dropped Gun | | btn=Go
* | Teleport to Map | Go To The Map | | btn=Go
* | Teleport to Lobby | Go To The Lobby | | btn=Go
* | Teleport to Secret | Go To The Secret Spot | | btn=Go
* | Role / player / gun / map / lobby / secret teleports with a configurable offset. | - |

misc aimlock | Enable Aimlock | Lock Camera On Target | Your camera stays pointed at the target.
* | Enable Aimlock Bind Button | On-Screen Aim Button | A round button on your screen that turns this on and off.
* | Aimlock Bind Button Size | Button Size |
* | Aimlock Wall Check | Ignore Targets Behind Walls |
* | Aimlock FOV Check | Only Lock Onto Players Inside The Circle |
* | Aimlock FOV Radius | Circle Size |
* | Aimlock Smoothness | How Smooth The Camera Moves | Higher is slower and smoother.
* | Aimlock Horizontal Prediction | Aim Ahead Of Sideways Movement |
* | Aimlock Target Player | Who To Lock Onto |
* | Refresh Aimlock Player List | Refresh Player List | | btn=Refresh
* | Clear Aimlock Player Selection | Clear My Choice | | btn=Clear
* | Aimlock Target Body Part | Aim At |
* | Aimlock Prediction | How Far Ahead To Aim |
* | Aimlock Quick Toggle | Key To Turn It On Or Off |
* | Tip: select Auto Murderer for automatic role targeting. Drag the round AIM button to move it. | Tip: pick Auto Murderer to lock onto the murderer automatically. Drag the round AIM button to move it. |

misc customize cursor | Enable Custom Cursor | Use A Custom Cursor | Replaces the crosshair with the design you pick.
* | Cursor Design | Cursor Design |
* | Enable Cursor Color | Color The Cursor |
* | Cursor Color | Cursor Color |
* | Cursor Artwork Scale | Cursor Size |
* | Custom Cursor ID | Your Own Cursor Picture Number | Paste the number of a picture to use it.
misc cursor plus | Enable Custom Cursor Plus | Use A Spinning Cursor |
* | Cursor Image ID | Cursor Picture Number |
* | Cursor Size | Cursor Size |
* | Cursor Rotate Speed | Spin Speed |

inventory unlimiter v5 | Persistence | - |
* | Unlimit Inventory | Remove The Item Limit | Lets your inventory show more items. Only you see this.
* | Max Items | Most Items To Show |
* | Initializing... | - |
main background | Enable Custom Background | Use A Backdrop Picture |
* | Background Image ID | Backdrop Picture Number |
* | Background Transparency | How See-Through |
]],

    values = [[
Silent Aim Mode | Noir=Normal; Tering=Alternate
Aimlock Target Body Part | Head=Head; HumanoidRootPart=Body
Aimlock Prediction | Medium (0.145)=Medium; Low (0.08)=Low; High (0.2)=High
Teleport Target | Murderer=Murderer; Sheriff=Sheriff; Random Player=Random Player
]],

    wordList = {
        { "Silent Aim", "Aim Assist" }, { "Wall Check", "Ignore Targets Behind Walls" },
        { "Prediction", "Aim Lead" }, { "Trigger Bot", "Auto Shoot" }, { "Hitbox", "Hit Area" },
        { "Xray", "See Through Walls" }, { "Noclip", "Walk Through Walls" }, { "Desync", "Fake Position" },
        { "Aimlock", "Camera Aim Lock" }, { "Bind Button", "On-Screen Button" }, { "Keybind", "Key" },
        { "Tracer", "Trail" }, { "ESP", "Player Markers" }, { "FOV", "Aim Circle" }, { "ping", "connection delay" },
        { "Ping", "Connection Delay" }, { "GUI", "Panel" }, { "Config", "Settings" }, { "Noir", "Peridot" },
        { "SFX", "Sounds" }, { "Telemetry", "Details" }, { "Cooldown", "Wait" }, { "Enable ", "Turn On " },
        { "Toggle", "Switch" }, { "Cache", "Memory" }, { "Whitelist", "Protect" },
    },
}

----------------------------------------------------------------------------
-- The rules that apply the data above. games/142823291.lua calls these for every control.
----------------------------------------------------------------------------

local function norm(value)
    return (tostring(value or ""):lower():gsub("[^%w%s]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- the label without leading emoji/symbols and trailing spaces, as the script wrote it
local function trimmed(value)
    return (tostring(value or ""):gsub("^[^%w]+", ""):gsub("%s+$", ""))
end

local function pluck(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Text.hasRussian(value)
    return tostring(value or ""):find("[\208\209]") ~= nil
end

function Text.words(value)
    value = tostring(value or "")
    for _, pair in ipairs(Text.wordList) do
        local from = pair[1]:gsub("%p", "%%%0")
        value = value:gsub(from, (pair[2]:gsub("%%", "%%%%")))
    end
    return value
end

-- Anything the data does not list: no symbols, normal capitals, plain words.
function Text.clean(value)
    value = trimmed(value)
    if value ~= "" and not value:find("%l") then
        value = value:lower():gsub("(%a)([%w']*)", function(first, rest)
            return first:upper() .. rest
        end)
    end
    return Text.words(value)
end

local KINDS = {
    Toggle = true, Button = true, Slider = true, Dropdown = true, PlayerDropdown = true,
    TextBox = true, Label = true, Paragraph = true, Colorpicker = true, Keybind = true,
}

local sectionByKey, exact, patterns, valueNames = {}, {}, {}, {}
for key, entry in pairs(Text.sections) do
    sectionByKey[key] = { page = entry[1], tab = entry[2], title = entry[3], intro = entry[4] }
end
for line in Text.controls:gmatch("[^\n]+") do
    local cells = {}
    for cell in (line .. " |"):gmatch("(.-)%s|") do
        cells[#cells + 1] = pluck(cell)
    end
    local entry = { section = cells[1], label = cells[2] or "", title = cells[3] or "", help = cells[4] or "", options = cells[5] or "" }
    entry.route = entry.options:match("route=(.-)%s*btn=") or entry.options:match("route=(.+)$")
    entry.button = entry.options:match("btn=(.+)$")
    local kind, label = entry.label:match("^(%u%a+):%s*(.+)$")
    if kind and KINDS[kind] then
        entry.kind, entry.label = kind, label
    end
    if entry.label:sub(1, 1) == "~" then
        entry.pattern = entry.label:sub(2)
        patterns[#patterns + 1] = entry
    else
        local id = norm(entry.label)
        if id == "" then
            id = entry.label -- text with no Latin letters (the script's few Russian labels) matches as written
        end
        exact[id] = exact[id] or {}
        table.insert(exact[id], entry)
    end
end
for line in Text.values:gmatch("[^\n]+") do
    local label, pairsText = line:match("^(.-)%s|%s(.+)$")
    if label then
        local map = {}
        for raw, shown in pairsText:gmatch("([^;=]+)=([^;]+)") do
            map[pluck(raw)] = pluck(shown)
        end
        valueNames[norm(label)] = map
    end
end

local PAGE_PREFIXES = { "MAIN", "WORLD", "VISUAL", "EMOTES", "MISC", "TROLL", "MAP", "FARM" }

-- "MAIN • SELF MODS" (and the one section that spells the bullet "u{2022}") => "main self mods".
-- Plugin sections arrive with "WORLD • " in front ("WORLD • FE Animations"); that prefix is
-- dropped when the data lists the section without it.
function Text.sectionKey(name)
    local key = norm((tostring(name or ""):gsub("u{2022}", "")))
    if sectionByKey[key] then
        return key
    end
    local withoutPrefix = key:gsub("^%a+ ", "", 1)
    if sectionByKey[withoutPrefix] then
        return withoutPrefix
    end
    return key
end

-- page, tab, title and intro for one of the script's sections
function Text.home(name, description)
    local home = sectionByKey[Text.sectionKey(name)]
    if home then
        return home.page, home.tab, home.title, home.intro
    end
    local plainName = tostring(name or ""):gsub("u{2022}", ""):gsub("\226\128\162", "")
    for _, prefix in ipairs(PAGE_PREFIXES) do
        plainName = plainName:gsub("^" .. prefix .. "%s+", "")
    end
    local title = Text.clean(plainName)
    if title == "" then
        title = Text.clean(name)
    end
    local intro = ""
    if type(description) == "string" and not Text.hasRussian(description) then
        intro = Text.clean(description)
    end
    return Text.fallback.page, Text.fallback.tab, title, intro
end

local function sectionMatches(entrySection, key)
    if entrySection == "*" then
        return true
    end
    if entrySection:sub(-1) == "*" then
        return key:sub(1, #entrySection - 1) == entrySection:sub(1, -2)
    end
    return entrySection == key
end

-- title, help, route and button text for one control. kind is "Toggle", "Button", ...
-- A title of "-" means the control is hidden.
function Text.describe(sectionKey, kind, label)
    local raw = trimmed(label)
    local candidates = exact[norm(raw)] or exact[raw]
    local best
    if candidates then
        for _, entry in ipairs(candidates) do
            if (entry.kind == nil or entry.kind == kind) and sectionMatches(entry.section, sectionKey) then
                local score = (entry.section ~= "*" and 2 or 0) + (entry.kind and 1 or 0)
                if not best or score > best.score then
                    best = { entry = entry, score = score }
                end
            end
        end
    end
    if best then
        return best.entry.title, best.entry.help, best.entry.route, best.entry.button
    end
    for _, entry in ipairs(patterns) do
        if (entry.kind == nil or entry.kind == kind) and sectionMatches(entry.section, sectionKey) then
            local capture = raw:match(entry.pattern)
            if capture then
                local title = entry.title:gsub("%%1", (capture:gsub("%%", "%%%%")))
                return Text.words(title), entry.help, nil, entry.button
            end
        end
    end
    if Text.hasRussian(raw) or raw == "" then
        return "-" -- never show text the player cannot read, or an empty line
    end
    return Text.clean(label), "", nil, nil, true -- the fifth value says the data had no entry
end

function Text.value(label, value)
    local map = valueNames[norm(label)]
    return map and map[tostring(value)] or tostring(value)
end

return Text
