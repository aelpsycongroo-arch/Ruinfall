--[[
=====================================================================================
  RUINFALL HUD + HALL MENU  -  ReplicatedStorage.HUD
=====================================================================================

This folder holds the LOOK of the game's screens. The code that fills them with live data
is StarterPlayer.StarterPlayerScripts.HUD (in-match) and .HubController (hall) - do not
move those.

  MainHUD  (ScreenGui)  the in-match HUD. Edit it, restyle it or replace it.
  HallMenu (ScreenGui)  the Ruinfall Hall menu (hub servers only): title plaque, lobby
                        board, your war party, notices. Same rules as MainHUD below.
                        Rebuild: require(game.ServerStorage.HUDTools.HallMenuBuilder:Clone()).Build()

WHY IT IS NOT IN StarterGui
  Everything in StarterGui is shown everywhere, including the hub (Ruinfall Hall).
  The HUD code clones MainHUD into the player's screen only on match servers and shows it
  only while a match is running (countdown / fight / end screen). Never in the hub or the
  pre-match lobby.

TO EDIT IT VISUALLY
  1. Drag MainHUD into StarterGui (you can now see it in the viewport).
  2. Edit it.
  3. Drag it BACK into ReplicatedStorage.HUD when done (otherwise it shows in the hub).

TO REPLACE IT WITH YOUR OWN
  Delete MainHUD and put your own ScreenGui here named "MainHUD". Use the element names
  below for anything you want the game to update. Anything you leave out is simply skipped
  (the Output window lists skipped names once) - nothing breaks.

TO GO BACK TO THE GENERATED ONE
  Command bar:  require(game.ServerStorage.HUDTools.MainHUDBuilder:Clone()).Build()
  (this overwrites MainHUD in this folder)

ELEMENT NAMES THE CODE LOOKS FOR  (paths inside MainHUD.Root)
  TopLeft                    painted plaques; "TEAM" / "YOUR FLAG" are part of the art
    TeamPanel.Frame / .Tint  ImageLabel   plaque art; Tint = banner + red accents (TeamTint)
    TeamPanel.Banner         ImageLabel   (optional) tinted with your team colour
    TeamPanel.TeamName       TextLabel    "CRIMSON"
    TeamPanel.Hourglass      ImageLabel   hidden when no ruin is coming
    TeamPanel.RuinLabel      TextLabel    "Next Ruin"
    TeamPanel.RuinTime       TextLabel    "0:46"
    FlagPanel.Frame / .Tint  ImageLabel   plaque art; Tint = little flag + red accents (TeamTint)
    FlagPanel.FlagIcon       ImageLabel   (optional) tinted with your team colour
    FlagPanel.Value          TextLabel    "2500 / 2500"
    FlagPanel.Bar.Fill       Frame        width = flag health
    MinionWave               TextLabel
  Scoreboard                 painted plaque (Frame); names / counts / bars / numbers are live
    Left / Right             Frame        team 1 / team 2, each with:
      .TeamName .Alive ("1/1") .Flag ("Flag 2500") .Bar.Fill (flag-health bar)
      .Tint (ImageLabel: that side's colour layer, tinted with that team's colour)
      optional: .Banner (ImageLabel, tinted) .Line (Frame, team colour)
  Scoreboard2 / Scoreboard3  copies of the Scoreboard plaque (same Left / Right parts) for
                             teams 3-4 and 5-6 in 4- / 6-team matches; they sit in the
                             ExtraBoards row under the main plaque and show only when needed.
                             Add Scoreboard4 etc. the same way for more teams.
    ExtraTeams               Frame        text labels for teams that have no plaque left
  Minimap                    Frame        (MinimapController)
    MapHolder                CanvasGroup  the map is drawn in here (keep it round with UICorner)
    Frame / FrameTint        ImageLabel   the border art; FrameTint = its red accents (TeamTint)
    ZoomIn / ZoomOut         ImageButton  the - / + medallions under the border
  BottomHUD                  Frame        the bottom bar (one piece of art, portrait + abilities)
    ArtLeft / ArtRight       ImageLabel   base art, red accents removed (grey)
    TintLeft / TintRight     ImageLabel   the accents only, in white -> recoloured to the team colour
  PlayerInfo                 (inside BottomHUD - found anywhere under Root)
    Portrait                 Frame        background = team colour (class colour if no team)
      .Avatar  ImageLabel (player headshot)   .Emblem  ImageLabel (class emblem)
    LevelBadge.Level         TextLabel    kills
    ClassName / Role         TextLabel    "FIGHTER" / "Balanced Bruiser"
    Gold.Value               TextLabel
    HealthBar.Fill / .Value / .Shield     health bar, "786 / 850", shield strip
    ManaBar.Fill / .Value                 mana bar (E / R item skills cost mana)
    Chips.Buff / .Fragment / .Status      each: .Label .Value .Stroke(UIStroke) .Icon
  AbilityBar                 (inside BottomHUD) keys: LM = MELEE, Q = BLOOD RUSH, E = ITEM, R = ITEM, MR = BOOTS
    SlotLM / SlotQ / SlotE / SlotR / SlotMR   each: .Icon .Glyph .Cooldown .Timer .Count.Value .Ready(UIStroke)
    NameLM ... NameMR        TextLabel    names under the slots
    KeyLM  ... KeyMR         TextLabel    keys on the tabs (NameMR is hidden: the boots cell is small)
    Passive1 / 2 / 3         Frame        PASSIVE 1-3 (2 x 2 grid with SlotMR, frames are in the art)
                                          each: .Icon .Glyph .Number .Caption .Highlight(UIStroke)
    SlotTooltip              Frame        hover text for SlotMR / Passive1-3: .Title .Sub .Body
  LastStand (.Hint .Timer), Channel (.Bar.Fill), CenterTitle, CenterSub

ATTRIBUTES YOU CAN PUT ON ANY ELEMENT
  TeamTint = true     the element follows your team colour (ImageColor3 for images,
                      BackgroundColor3 for frames). Use WHITE art for it to tint cleanly.
  DesktopOnly = true  hidden on phones / tablets (the touch buttons replace the ability bar)

TO USE NEW TEAM-TINTED ART
  Upload two images: the art with the coloured accents made grey (base), and the accents
  alone in white on transparent (tint). Put the tint image on top with TeamTint = true.

HALLMENU ELEMENT NAMES  (paths inside HallMenu.Root)
  LeftColumn.Title.Classes                  Frame   class emblems are added here
  LeftColumn.LobbyBoard.Lobby1 .. Lobby4    Frame   each: .Tint (lobby colour) .Selected
                                            .LobbyName .Sub .Info .Join (TextButton)
  WarParty                                  Frame   shown while you are in a lobby
    Header.Tint .Heading .Gate .Count
    Panel.Tint .Members (ScrollingFrame) .MemberTemplate (.PlayerName .Host)
    Panel.Mode1 .. Mode3, .HostHint, .Start, .Leave, .StudioNote
  Notice                                    Frame   .Tint (notice colour) .Message
  Button looks: HUD.Theme.ButtonStyles (Primary / Gold / Dark / Danger / Disabled).

ART (rbxassetid) used by the generated layout - swap the Image property on the
ImageLabels to use your own. The list also lives in StarterPlayerScripts.HUD.Theme.
]]

return nil
