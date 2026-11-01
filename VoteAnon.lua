--[[
  VoteAnon
  --------
  Bob (le seul a avoir l'addon) cree un sondage a 2-4 choix et le publie en
  clair dans le groupe, le raid ou la guilde (commande /vote pour ouvrir la
  fenetre). Les autres joueurs n'ont PAS besoin de l'addon : ils votent en
  tapant simplement 1, 2, 3 ou 4 dans ce meme canal de chat. Le client de
  Bob ecoute ce canal pendant la duree du sondage et ne retient, pour
  chaque joueur, que son DERNIER message numerique valide (un joueur peut
  changer d'avis). Pendant le vote, une petite fenetre de suivi affiche le
  compte a rebours et un bouton pour arreter le sondage immediatement (le
  resultat est alors annonce comme si le minuteur etait arrive a echeance,
  simplement avec le temps reellement ecoule). A la fin (minuteur ou arret
  manuel), une fenetre de resultats s'affiche chez Bob avec un bouton pour
  publier le classement dans le meme canal.

  Le vote est "anonyme" au sens ou les autres participants ne voient jamais
  qui a vote pour quoi : seul Bob voit le detail (et encore, seulement le
  compte final), tout le monde ne voit que les messages "1"/"2"/"3"/"4" dans
  le chat normal.

  Toute l'interface est construite en Lua pur (CreateFrame), sans fichier
  XML : le XML declaratif posait des problemes de compatibilite non
  resolus sur ce client (Backdrop, FontString, maxLetters non reconnus),
  alors que la construction en Lua fonctionne de maniere fiable.
]]

local addonName = ...

VoteAnonDebug = {}
local previousErrorHandler = geterrorhandler()
seterrorhandler(function(msg)
  table.insert(VoteAnonDebug, 1, date("%H:%M:%S") .. " " .. tostring(msg))
  if previousErrorHandler then previousErrorHandler(msg) end
end)

-- Icones de marqueur de raid (etoile, cercle, diamant, triangle) : definies
-- ici, avant la creation des widgets, pour pouvoir les utiliser tout de
-- suite sur les labels des 4 lignes de choix.
--  - ChoiceIcon : sequence de texture brute "|T...|t", pour l'affichage
--    LOCAL (labels de la fenetre, popup de resultats, fenetre de suivi).
--  - ChoiceChatIcon : tag "{rt1}".."{rt4}", a utiliser UNIQUEMENT dans les
--    messages envoyes via SendChatMessage. C'est le mecanisme natif du
--    client qui convertit ce tag en icone au moment de l'affichage, CHEZ
--    CHAQUE JOUEUR QUI REÇOIT le message.
local RAID_ICON_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local function ChoiceIcon(index)
  return "|T"..RAID_ICON_PATH..index..":16|t"
end

local function ChoiceChatIcon(index)
  return "{rt"..index.."}"
end

--------------------------------------------------------------------------
-- Fenetre principale (creation du sondage)
--------------------------------------------------------------------------

local frame = CreateFrame("Frame", "VoteAnonMainFrame", UIParent, "BackdropTemplate")
frame:SetSize(400, 300)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:SetFrameStrata("DIALOG")
frame:SetToplevel(true)
frame:SetBackdrop({
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
frame:Hide()

local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", -4, -4)

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(VoteAnonL.TITLE)

local promptEditBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
promptEditBox:SetSize(360, 25)
promptEditBox:SetPoint("TOPLEFT", 16, -48)
promptEditBox:SetAutoFocus(false)
promptEditBox:SetMaxLetters(80)

local promptLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
promptLabel:SetPoint("BOTTOMLEFT", promptEditBox, "TOPLEFT", 0, 2)
promptLabel:SetJustifyH("LEFT")
promptLabel:SetText(VoteAnonL.QUESTION_LABEL)

-- 4 lignes de choix fixes (pas de bouton "ajouter" : une ligne vide n'est
-- simplement pas comptee comme un choix, voir StartVote).
local choiceEditBoxes = {}
local CHOICE_ROW_Y = { -84, -118, -152, -186 }
local CHOICE_LABEL_Y = { -88, -122, -156, -190 }
for i = 1, 4 do
  local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 16, CHOICE_LABEL_Y[i])
  label:SetJustifyH("LEFT")
  label:SetText(ChoiceIcon(i) .. " " .. i .. ".")

  local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  editBox:SetSize(330, 25)
  editBox:SetPoint("TOPLEFT", 54, CHOICE_ROW_Y[i])
  editBox:SetAutoFocus(false)
  editBox:SetMaxLetters(30)
  choiceEditBoxes[i] = editBox
end

local durationLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
durationLabel:SetPoint("BOTTOMLEFT", 16, 45)
durationLabel:SetJustifyH("LEFT")
durationLabel:SetText(VoteAnonL.DURATION_LABEL)

local duration30Button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
duration30Button:SetSize(70, 22)
duration30Button:SetPoint("BOTTOMLEFT", 70, 40)
duration30Button:SetText(VoteAnonL.DUR_30)

local duration60Button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
duration60Button:SetSize(65, 22)
duration60Button:SetPoint("BOTTOMLEFT", 145, 40)
duration60Button:SetText(VoteAnonL.DUR_60)

local duration120Button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
duration120Button:SetSize(65, 22)
duration120Button:SetPoint("BOTTOMLEFT", 215, 40)
duration120Button:SetText(VoteAnonL.DUR_120)

local groupButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
groupButton:SetSize(80, 25)
groupButton:SetPoint("BOTTOMLEFT", 16, 8)
groupButton:SetText(VoteAnonL.GROUP)

local raidButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
raidButton:SetSize(80, 25)
raidButton:SetPoint("BOTTOMLEFT", 100, 8)
raidButton:SetText(VoteAnonL.RAID)

local guildButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
guildButton:SetSize(80, 25)
guildButton:SetPoint("BOTTOMLEFT", 184, 8)
guildButton:SetText(VoteAnonL.GUILD)

-- Bouton de test : lance le vote via /me (toujours disponible, meme seul,
-- pas besoin de groupe/raid/guilde). Voir ResolveChannel/CHANNEL_EVENTS.
local meButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
meButton:SetSize(64, 25)
meButton:SetPoint("BOTTOMLEFT", 270, 8)
meButton:SetText(VoteAnonL.ME)

local MIN_CHOICES = 2

local selectedDuration = 30

-- Etat du vote en cours (independant du formulaire, pour survivre a la
-- fermeture de la fenetre de creation une fois le vote lance)
local voting = false
local votes = {}            -- [nomExpediteur] = indexDuChoix, dernier message recu qui gagne
local activeChoices = {}
local activePrompt = ""
local activeRealChannel = nil   -- "PARTY" / "RAID" / "GUILD"
local registeredEvents = {}
local voteStartTime = 0
local voteDurationSeconds = 0
local countdownTicker = nil
local StopVote -- forward-declare : assignee plus loin, juste apres EndVote

-- Fonction utilitaire pour afficher un message dans le chat de Bob
local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00VoteAnon:|r "..msg)
end

local function FormatDuration(seconds)
  if seconds == 30 then return VoteAnonL.DUR_30
  elseif seconds == 60 then return VoteAnonL.DUR_60
  else return VoteAnonL.DUR_120 end
end

local function TruncateForDisplay(text, maxLen)
  if #text <= maxLen then return text end
  local cut = maxLen
  while cut > 0 do
    local b = text:byte(cut + 1)
    if not b or b < 0x80 or b >= 0xC0 then break end
    cut = cut - 1
  end
  return text:sub(1, cut) .. "..."
end

--------------------------------------------------------------------------
-- Fenetre de suivi affichee pendant un vote : compte a rebours + bouton
-- pour arreter le sondage avant la fin (voir StopVote/EndVote plus bas).
--------------------------------------------------------------------------

local progressFrame = CreateFrame("Frame", "VoteAnonProgressFrame", UIParent, "BackdropTemplate")
progressFrame:SetSize(260, 110)
progressFrame:SetPoint("TOP", UIParent, "TOP", 0, -150)
progressFrame:SetFrameStrata("DIALOG")
progressFrame:SetBackdrop({
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
progressFrame:SetBackdropColor(0, 0, 0, 0.85)
progressFrame:Hide()

local progressTitle = progressFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
progressTitle:SetPoint("TOP", progressFrame, "TOP", 0, -12)
progressTitle:SetText(VoteAnonL.PROGRESS_TITLE)

local progressPromptText = progressFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
progressPromptText:SetPoint("TOP", progressTitle, "BOTTOM", 0, -6)
progressPromptText:SetWidth(230)
progressPromptText:SetJustifyH("CENTER")

local progressCountdownText = progressFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
progressCountdownText:SetPoint("TOP", progressPromptText, "BOTTOM", 0, -8)

local progressStopButton = CreateFrame("Button", "VoteAnonProgressStopButton", progressFrame, "UIPanelButtonTemplate")
progressStopButton:SetSize(140, 22)
progressStopButton:SetPoint("BOTTOM", progressFrame, "BOTTOM", 0, 10)
progressStopButton:SetText(VoteAnonL.STOP_BUTTON)
progressStopButton:SetScript("OnClick", function() StopVote() end)

local function UpdateProgressDisplay()
  local remaining = math.max(0, math.ceil(voteStartTime + voteDurationSeconds - GetTime()))
  progressCountdownText:SetText(remaining .. " s")
end

-- Determine le canal de chat reel a utiliser pour un canal logique
-- ("GROUP" -> PARTY ou RAID selon le contexte). Renvoie nil si le joueur
-- n'est pas dans le contexte requis (pas de groupe, pas de guilde...).
-- "ME" (bouton de test) renvoie toujours "EMOTE" : disponible seul, sans
-- groupe/raid/guilde, pour tester tout le flux sans second joueur.
local function ResolveChannel(channel)
  if channel == "GROUP" and IsInGroup() then
    return IsInRaid() and "RAID" or "PARTY"
  elseif channel == "RAID" and IsInRaid() then
    return "RAID"
  elseif channel == "GUILD" and IsInGuild() then
    return "GUILD"
  elseif channel == "ME" then
    return "EMOTE"
  end
  return nil
end

-- Evenements de chat a ecouter pour chaque canal reel. Un message envoye
-- par le chef de groupe/raid arrive via un evenement "_LEADER" distinct de
-- l'evenement normal, il faut donc ecouter les deux.
local CHANNEL_EVENTS = {
  PARTY = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" },
  RAID  = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" },
  GUILD = { "CHAT_MSG_GUILD" },
  -- Canal de test "Me" : l'annonce part en /me, mais un joueur qui tape
  -- juste "1" dans le chat envoie ca par defaut en /say, pas en /me. On
  -- ecoute donc les deux pour que le test solo fonctionne naturellement.
  EMOTE = { "CHAT_MSG_EMOTE", "CHAT_MSG_SAY" },
}

--------------------------------------------------------------------------
-- Formulaire de creation du vote
--------------------------------------------------------------------------

local function Trim(text)
  return text:match("^%s*(.-)%s*$")
end

-- Selection de la duree (3 boutons façon "radio" : le bouton selectionne
-- est grise/desactive, les deux autres restent cliquables)
local function SelectDuration(seconds)
  selectedDuration = seconds
  duration30Button:SetEnabled(seconds ~= 30)
  duration60Button:SetEnabled(seconds ~= 60)
  duration120Button:SetEnabled(seconds ~= 120)
end

duration30Button:SetScript("OnClick", function() SelectDuration(30) end)
duration60Button:SetScript("OnClick", function() SelectDuration(60) end)
duration120Button:SetScript("OnClick", function() SelectDuration(120) end)

-- Reinitialise le formulaire (nouveau sondage vierge). Appele a chaque
-- fermeture de la fenetre : si Bob ferme sans lancer de vote, rien n'est
-- conserve ; si un vote vient d'etre lance, le formulaire est aussi repris
-- a zero pour le prochain sondage (le vote en cours vit dans son propre
-- etat "active*", independant de ce formulaire).
local function ResetForm()
  promptEditBox:SetText("")
  for _, editBox in ipairs(choiceEditBoxes) do
    editBox:SetText("")
  end
  SelectDuration(30)
end
frame:SetScript("OnHide", ResetForm)

--------------------------------------------------------------------------
-- Ecoute des votes dans le chat (aucun addon requis chez les votants)
--------------------------------------------------------------------------

-- Un message est considere comme un vote pour le chiffre X si, une fois
-- l'espace et la ponctuation de fin (!, ., ?, ...) retires, il ne reste
-- QUE le chiffre X repete une ou plusieurs fois (" 2 " -> 2, "2!" -> 2,
-- "222222" -> 2, "2." -> 2). Un message avec des chiffres differents
-- ("12", "1 2") reste ignore : trop ambigu pour deviner l'intention.
-- NOTE : la premiere version utilisait un pattern Lua avec back-reference
-- ("^(%d)%1*$"), qui s'est revele ne pas fonctionner correctement dans cet
-- environnement (confirme par test en jeu : renvoyait toujours nil, meme
-- pour un simple "2"). Remplace par une verification manuelle equivalente,
-- sans back-reference.
local function ExtractVoteDigit(text)
  local trimmed = text:match("^%s*(.-)%s*$")
  trimmed = trimmed:gsub("%p+$", "")
  if trimmed == "" then return nil end
  local firstChar = trimmed:sub(1, 1)
  if not firstChar:match("%d") then return nil end
  if trimmed:gsub(firstChar, "") ~= "" then return nil end -- chiffres differents dans le message
  return tonumber(firstChar)
end

local voteListenFrame = CreateFrame("Frame")
voteListenFrame:SetScript("OnEvent", function(self, event, text, playerName)
  if not voting then return end

  -- Les messages de Bob comptent comme ceux des autres : il peut voter lui
  -- aussi. Son annonce et ses choix ne risquent pas d'etre pris pour des
  -- votes, ExtractVoteDigit n'accepte qu'un message fait d'un seul chiffre.
  local choiceIndex = ExtractVoteDigit(text)
  if not choiceIndex or choiceIndex < 1 or choiceIndex > #activeChoices then return end

  votes[playerName] = choiceIndex -- le dernier message valide de ce joueur ecrase le precedent
end)

local function RegisterVoteListening(realChannel)
  registeredEvents = CHANNEL_EVENTS[realChannel] or {}
  for _, evt in ipairs(registeredEvents) do
    voteListenFrame:RegisterEvent(evt)
  end
end

local function UnregisterVoteListening()
  for _, evt in ipairs(registeredEvents) do
    voteListenFrame:UnregisterEvent(evt)
  end
  registeredEvents = {}
end

--------------------------------------------------------------------------
-- Deroulement du vote
--------------------------------------------------------------------------

local function ShowResultsPopup(resultsHeader, displayLines, displayWinner, chatLines, chatWinner)
  local text = resultsHeader .. "\n\n" .. table.concat(displayLines, "\n")
  if displayWinner then
    text = text .. "\n\n" .. displayWinner
  end

  StaticPopupDialogs["VOTEANON_RESULTS"] = {
    text = text,
    button1 = VoteAnonL.PUBLISH_BUTTON,
    button2 = VoteAnonL.CLOSE_BUTTON,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function()
      if not activeRealChannel then return end
      SendChatMessage(resultsHeader, activeRealChannel)
      for _, line in ipairs(chatLines) do
        SendChatMessage(line, activeRealChannel)
      end
      if chatWinner then
        SendChatMessage(chatWinner, activeRealChannel)
      end
    end,
  }
  StaticPopup_Show("VOTEANON_RESULTS")
end

-- Termine le vote, que ce soit parce que le minuteur est arrive a
-- echeance OU parce que Bob a clique sur "Arreter le vote" (StopVote).
local function EndVote()
  if not voting then return end
  voting = false
  UnregisterVoteListening()
  if countdownTicker then countdownTicker:Cancel(); countdownTicker = nil end
  progressFrame:Hide()

  local elapsedSeconds = math.max(0, math.floor((GetTime() - voteStartTime) + 0.5))

  local counts = {}
  for i = 1, #activeChoices do counts[i] = 0 end
  for _, choiceIndex in pairs(votes) do
    counts[choiceIndex] = counts[choiceIndex] + 1
  end

  local displayLines, chatLines = {}, {}
  local maxCount = 0
  for i, c in ipairs(activeChoices) do
    displayLines[i] = ChoiceIcon(i) .. " " .. i .. ". " .. string.format(VoteAnonL.RESULT_LINE_FMT, c, counts[i])
    chatLines[i] = ChoiceChatIcon(i) .. " " .. i .. ". " .. string.format(VoteAnonL.RESULT_LINE_FMT, c, counts[i])
    if counts[i] > maxCount then maxCount = counts[i] end
  end

  local displayWinner, chatWinner
  if maxCount == 0 then
    displayWinner = VoteAnonL.NO_VOTES
    chatWinner = displayWinner
  else
    local displayWinners, chatWinners = {}, {}
    for i, c in ipairs(activeChoices) do
      if counts[i] == maxCount then
        table.insert(displayWinners, ChoiceIcon(i) .. " " .. c)
        table.insert(chatWinners, ChoiceChatIcon(i) .. " " .. c)
      end
    end
    if #displayWinners == 1 then
      displayWinner = string.format(VoteAnonL.WINNER_FMT, displayWinners[1], maxCount)
      chatWinner = string.format(VoteAnonL.WINNER_FMT, chatWinners[1], maxCount)
    else
      displayWinner = string.format(VoteAnonL.TIE_FMT, maxCount, table.concat(displayWinners, ", "))
      chatWinner = string.format(VoteAnonL.TIE_FMT, maxCount, table.concat(chatWinners, ", "))
    end
  end

  local resultsHeader = string.format(VoteAnonL.RESULTS_HEADER_FMT, elapsedSeconds, activePrompt)

  Print(resultsHeader)
  for _, line in ipairs(displayLines) do Print(line) end
  Print(displayWinner)

  ShowResultsPopup(resultsHeader, displayLines, displayWinner, chatLines, chatWinner)
end

-- Arret manuel : simple raccourci vers EndVote.
StopVote = function()
  if not voting then return end
  EndVote()
end

-- Nom localise du canal affiche dans le message "Vote lance sur ..."
local CHANNEL_DISPLAY_NAMES = {
  GROUP = VoteAnonL.CHANNEL_GROUP,
  RAID = VoteAnonL.CHANNEL_RAID,
  GUILD = VoteAnonL.CHANNEL_GUILD,
  ME = VoteAnonL.CHANNEL_ME,
}

local function StartVote(channel)
  if voting then
    Print(VoteAnonL.ALREADY_VOTING)
    return
  end

  -- Les lignes vides ne comptent pas comme un choix : on les ignore et on
  -- renumerote les choix restants en 1..N (c'est ce numero, pas la position
  -- de la ligne dans la fenetre, qui sera annonce et vote dans le chat).
  local filledChoices = {}
  for _, editBox in ipairs(choiceEditBoxes) do
    local text = Trim(editBox:GetText())
    if text ~= "" then
      table.insert(filledChoices, text)
    end
  end
  if #filledChoices < MIN_CHOICES then
    Print(string.format(VoteAnonL.NEED_MIN_CHOICES, MIN_CHOICES))
    return
  end

  local prompt = promptEditBox:GetText()
  if prompt == "" then
    Print(VoteAnonL.NEED_PROMPT)
    return
  end

  local realChannel = ResolveChannel(channel)
  if not realChannel then
    Print(VoteAnonL.CANT_SEND)
    return
  end

  activeChoices = filledChoices
  activePrompt = prompt
  activeRealChannel = realChannel

  voting = true
  votes = {}
  voteStartTime = GetTime()
  voteDurationSeconds = selectedDuration

  local header = string.format(VoteAnonL.ANNOUNCE_FMT, UnitName("player"), FormatDuration(selectedDuration),
      activePrompt, #activeChoices)
  SendChatMessage(header, realChannel)
  for i, c in ipairs(activeChoices) do
    SendChatMessage(ChoiceChatIcon(i) .. " " .. i .. ". " .. c, realChannel)
  end

  RegisterVoteListening(realChannel)
  Print(string.format(VoteAnonL.VOTE_LAUNCHED_FMT, CHANNEL_DISPLAY_NAMES[channel] or channel, FormatDuration(selectedDuration)))

  progressPromptText:SetText(TruncateForDisplay(activePrompt, 40))
  UpdateProgressDisplay()
  progressFrame:Show()
  if countdownTicker then countdownTicker:Cancel() end
  countdownTicker = C_Timer.NewTicker(1, UpdateProgressDisplay)

  frame:Hide()

  C_Timer.After(selectedDuration, EndVote)
end

groupButton:SetScript("OnClick", function() StartVote("GROUP") end)
raidButton:SetScript("OnClick", function() StartVote("RAID") end)
guildButton:SetScript("OnClick", function() StartVote("GUILD") end)
meButton:SetScript("OnClick", function() StartVote("ME") end)

SLASH_VOTEANON1 = "/vote"
SlashCmdList["VOTEANON"] = function()
  frame:Show()
end

ResetForm()
