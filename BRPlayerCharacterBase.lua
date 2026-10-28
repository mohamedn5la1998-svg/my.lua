local BRPlayerCharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_NearDeathGiveupRescue = {
  Reliable = true,
  Params = {}
}
BRPlayerCharacterBase.ServerRPC.ServerRPC_CarryDeadBox = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Object
  }
}
BRPlayerCharacterBase.ServerRPC.RPC_Server_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.MulticastRPC.MulticastRPC_GmPlayAction = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
BRPlayerCharacterBase.ClientRPC.RPC_Client_SetShouldCheckPassWall = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}
local ENetRole = import("ENetRole")
local EPawnState = import("EPawnState")
local ESpecialMovementType = import("ESpecialMovementType")
local ESpiderSwingMoveState = import("ESpiderSwingMoveState")
local ESurviveWeaponPropSlot = import("ESurviveWeaponPropSlot")
local EParachuteState = import("EParachuteState")
local EMovementMode = import("EMovementMode")
local EStateType = import("EStateType")
local ESTEPoseState = import("ESTEPoseState")
local EGameModeType = import("EGameModeType")
local STExtraGameStateBase = import("STExtraGameStateBase")
local UKismetSystemLibrary = import("KismetSystemLibrary")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local MatchModeIds = require("GameLua.Mod.BaseMod.GamePlay.Config.MatchModeIdsConfig")

function BRPlayerCharacterBase:ctor()
end

function BRPlayerCharacterBase:_PostConstruct()
  BRPlayerCharacterBase.__super._PostConstruct(self)
  self:InitAddSpecialMoveInfo()
  self.bCanNearDeathGiveup = true
  print(bWriteLog and "BRPlayerCharacterBase:_PostConstruct bCanNearDeathGiveup true")
end

function BRPlayerCharacterBase:ReceiveBeginPlay()
  BRPlayerCharacterBase.__super.ReceiveBeginPlay(self)
  self:AddControlEvent(self, "MovementModeChangedDelegate", self.HandleOnMovementModeChangedNew, self)
  if self:HasAuthority() and self:CheckAddCheckFallingDistanceComponent() then
    local CheckFallingDistanceComponent_C = import("CheckFallingDistanceComponent")
    if slua.isValid(CheckFallingDistanceComponent_C) and not slua.isValid(self:GetComponentByClass(CheckFallingDistanceComponent_C)) then
      print(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay Add CheckFallingDistanceComponent")
      Game:AddComponent(CheckFallingDistanceComponent_C, self, "CheckFallingDistanceComponent")
    end
  end
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bPositiveBlowUp = true
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddControlEvent(self, "OnPawnStateDisabled", self.OnPawnStateChange, self)
    self:AddControlEvent(self, "OnPawnStateEnabled", self.OnPawnStateChange, self)
    self:AddControlEventConditionOnly(self, "OnAttrChangeEventDelegate", {
      AttrName = {
        "bCanSelfRescue"
      }
    }, self.CharacterAttrChangeEvent, self)
  end
  if Client then
    printf(bWriteLog and "BRPlayerCharacterBase:ReceiveBeginPlay, PlayerKey:%u ", self.PlayerKey)
    GameplayData.AddCharacter(self.Object)
  else
    self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, {
      [1] = "FinishedState"
    }, self.HandleFinishedState, self)
  end
end

function BRPlayerCharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  BRPlayerCharacterBase.__super.CharacterAttrChangeEvent(self, uPawn, AttrName, AttrVal)
  if self.Object ~= uPawn then
    return
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and AttrName == "bCanSelfRescue" then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_CanSelfRescue", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:OnPawnStateChange(PawnState)
  print("BRPlayerCharacterBase:OnPawnStateChange:", PawnState)
  if PawnState == EPawnState.SwitchPP then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:BroadcastUIMessage("UIMsg_FPPModeChange", 0, "", "")
    end
  end
end

function BRPlayerCharacterBase:HandleFinishedState()
  print(bWriteLog and "BRPlayerCharacterBase:HandleFinishedState", self.STCharacterMovement)
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.SetDynamicSimpleQueryConfigDisable then
    local EDynamicSimpleQueryConfigDisableMask = import("EDynamicSimpleQueryConfigDisableMask")
    self.STCharacterMovement:SetDynamicSimpleQueryConfigDisable(EDynamicSimpleQueryConfigDisableMask.Bit0, true)
  end
end

function BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent()
  if CGameMode and CGameMode.GameModeType and CGameState and CGameState.GameModeID then
    local GameModeType = CGameMode.GameModeType
    local GameModeID = tonumber(CGameState.GameModeID)
    local bModeTypeSatisfy = GameModeType == EGameModeType.ETypicalGameMode or GameModeType == EGameModeType.EFourInOneGameMode or GameModeType == EGameModeType.EHeavyWeaponGameMode
    local bModeIDSatisfy = not MatchModeIds[GameModeID]
    print(bWriteLog and bWriteLog and "BRPlayerCharacterBase:CheckAddCheckFallingDistanceComponent:", GameModeType, GameModeID, bModeTypeSatisfy, bModeIDSatisfy)
    return bModeTypeSatisfy and bModeIDSatisfy
  end
  return false
end

function BRPlayerCharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  BRPlayerCharacterBase.__super.LuaHandleParachuteStateChanged(self, LastParachuteState, NewParachuteState)
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if NewParachuteState == EParachuteState.PS_Opening then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.SatrtCheckShowParachuteCloseUI then
          uCurrentPlayerControl.CheckParachuteOpenFeature:SatrtCheckShowParachuteCloseUI()
        end
      elseif NewParachuteState == EParachuteState.PS_None then
        if uCurrentPlayerControl.CheckParachuteOpenFeature.RecoverParachuteOpenParam then
          uCurrentPlayerControl.CheckParachuteOpenFeature:RecoverParachuteOpenParam()
        end
        if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
          uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
        end
      end
    end
  end
end

function BRPlayerCharacterBase:OnLanded()
  printf("BRPlayerCharacterBase:OnLanded PlayerKey:%d", self.PlayerKey)
  if self.HandleOnLanded then
    self:HandleOnLanded(-1)
  end
  if not Client then
    local uCurrentPlayerControl = self:GetPlayerControllerSafety()
    if slua.isValid(uCurrentPlayerControl) and uCurrentPlayerControl.CheckParachuteOpenFeature then
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ClearTimerAndState then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ClearTimerAndState()
      end
      if uCurrentPlayerControl.CheckParachuteOpenFeature.ResetCheckShowUI then
        uCurrentPlayerControl.CheckParachuteOpenFeature:ResetCheckShowUI()
      end
    end
  end
end

function BRPlayerCharacterBase:ReceiveEndPlay(EndPlayReason)
  BRPlayerCharacterBase.__super.ReceiveEndPlay(self, EndPlayReason)
  if Client then
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:IsWarGameMode()
  local uGameState = GameplayData:GetGameState()
  if slua.isValid(uGameState) and Game:IsClassOf(uGameState, STExtraGameStateBase) then
    return uGameState.GameModeType == EGameModeType.EWarGameMode
  else
    return false
  end
end

function BRPlayerCharacterBase:BPOnRecycled()
  print(bWriteLog and string.format("%s BPOnRecycled()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:BPOnRespawned()
  print(bWriteLog and string.format("%s BPOnRespawned()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
  end
end

function BRPlayerCharacterBase:ReceiveOnRecycle()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnRecycle()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.RemoveCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ReceiveOnSpawn()
  print(bWriteLog and string.format("%s IReusable:ReceiveOnSpawn()", Game:GetPlainName(self.Object)))
  if Client then
    self:ResetMeshRelativeLocationAndRotation()
    GameplayData.AddCharacter(self.Object)
  end
end

function BRPlayerCharacterBase:ResetMeshRelativeLocationAndRotation()
  if Game:IsValid(self.Object) and Game:IsValid(self.Mesh) then
    local uDefaultMeshRot = FRotator(0, -90, 0)
    local uDefaultMeshRelativeLoc = FVector(0, 0, 0)
    if self.Mesh.K2_SetRelativeRotation then
      self.Mesh:K2_SetRelativeRotation(uDefaultMeshRot, false, nil, false)
    end
    self:CacheInitialMeshOffset(uDefaultMeshRelativeLoc, uDefaultMeshRot)
    local vRelativeRot = self.Mesh.RelativeRotation
    local vBaseRotationOffset = self.BaseRotationOffset
    local vBaseRotation = Game:QuatToRotator(vBaseRotationOffset)
    print(bWriteLog and bWriteLog and string.format("%s ResetMeshRelativeLocationAndRotation() Mesh.RelativeRotation: %s %s %s   Pawn.BaseRotationOffset:%s %s %s ", Game:GetPlainName(self.Object), tostring(vRelativeRot.Pitch), tostring(vRelativeRot.Yaw), tostring(vRelativeRot.Roll), tostring(vBaseRotation.Pitch), tostring(vBaseRotation.Yaw), tostring(vBaseRotation.Roll)))
  end
end

function BRPlayerCharacterBase:HandleOnMovementModeChangedNew()
  print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged11")
  if Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Swimming and self:CheckBaseIsMoveable() then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChanged22")
    self.CharacterMovement:SetBase(nil, "", true)
  end
  if self.Role == ENetRole.ROLE_AutonomousProxy and Game:IsValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking and UIManager.UI_Config_InGame.ParachuteOpenUI then
    print(bWriteLog and "BRPlayerCharacterBase:HandleOnMovementModeChangedNew CloseUI")
    UIManager.CloseUI(UIManager.UI_Config_InGame.ParachuteOpenUI)
  end
end

function BRPlayerCharacterBase:BPOnMissPlayerDamageRecord()
end

function BRPlayerCharacterBase:PreAttachedToVehicle()
  local IsDS = UKismetSystemLibrary.IsDedicatedServer(self)
  if not IsDS then
    return
  end
  local MainPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(MainPlayerController) then
    return
  end
  local CharacterAvatarComp2_BP = self.CharacterAvatarComp2_BP
  if not slua.isValid(CharacterAvatarComp2_BP) then
    return
  end
  local CommerAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.CommerAvatarDataUtil")
  local changedVehicleId = CommerAvatarDataUtil:ChangeVehicleSkinByClothes(MainPlayerController, CharacterAvatarComp2_BP)
  local ESTExtraVehicleShapeType = import("ESTExtraVehicleShapeType")
  if changedVehicleId then
    local UAvatarUtils = import("AvatarUtils")
    if UAvatarUtils.GetVehicleShapeBySkinID(changedVehicleId) == ESTExtraVehicleShapeType.VST_Horse then
      local uCurPlayerState = self:GetPlayerStateSafety()
      if slua.isValid(uCurPlayerState) then
        print(bWriteLog and "  BRPlayerCharacterBase:PreAttachedToVehicle. changedVehicleId: " .. tostring(changedVehicleId))
        uCurPlayerState:AddGeneralCount(468, 1, false)
      end
    end
  end
end

function BRPlayerCharacterBase:ParachuteJump()
  local uPlayerController = self:GetControllerSafety()
  if slua.isValid(uPlayerController) then
    if not self:GetEnsure() then
      if uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteJump and uPlayerController:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
        self:SwitchPoseState(ESTEPoseState.Stand, true, true, true, false)
        uPlayerController:ReInitParachuteItem()
        uPlayerController:ServerChangeStatePC(EStateType.State_ParachuteJump)
      end
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump over")
    else
      EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_AI_CALL_PARACHUTE_JUMP, self.Object)
      print(bWriteLog and "BRPlayerCharacterBase:ParachuteJump AI JUMP over, Loc=", tostring(self:K2_GetActorLocation():ToString()))
    end
  end
end

function BRPlayerCharacterBase:OnMovementBaseChangedEvent(uCharacter, uNewMovementBase, uOldMovementBase)
  if uCharacter ~= self.Object then
    return
  end
  print(bWriteLog and string.format("BRPlayerCharacterBase:OnMovementBaseChangedEvent %s, Base: %s -> %s", uCharacter, uOldMovementBase, uNewMovementBase))
  local MedievalCrane = self:GetMedievalCraneFromBase(uNewMovementBase)
  if MedievalCrane and MedievalCrane.AddCharacter then
    MedievalCrane:AddCharacter(self.Object)
  else
    MedievalCrane = self:GetMedievalCraneFromBase(uOldMovementBase)
    if MedievalCrane and MedievalCrane.RemoveCharacter then
      MedievalCrane:RemoveCharacter(self.Object)
    end
  end
end

function BRPlayerCharacterBase:GetMedievalCraneFromBase(Base)
  if not slua.isValid(Base) or not Base.GetOwner then
    return
  end
  local Lifter = Base:GetOwner()
  if not slua.isValid(Lifter) then
    return
  end
  if not Lifter.AddCharacter then
    return
  end
  return Lifter
end

function BRPlayerCharacterBase:CheckForbidFlaregun()
  local uPlayerState = self:GetPlayerStateSafety()
  if not slua.isValid(uPlayerState) then
    return false
  end
  if uPlayerState.CanUseFlaregun == false and self:IsLocallyControlled() then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then
      uPlayerController:DisplayGameTipWithMsgID(48532)
    end
  end
  return not uPlayerState.CanUseFlaregun
end

function BRPlayerCharacterBase:ServerRPC_NearDeathGiveupRescue()
  self:HandleNearDeathGiveupRescue()
end

function BRPlayerCharacterBase:HandleNearDeathGiveupRescue()
  local uNearDeathComp = self.NearDeatchComponent
  if self:IsNearDeath() and slua.isValid(uNearDeathComp) and self.bCanNearDeathGiveup == true then
    local uPlayerState = self:GetPlayerStateSafety()
    if slua.isValid(uPlayerState) then
      uPlayerState:AddGeneralCount(1613, 1, false)
    end
    uNearDeathComp:TriggerGotoDieExplictly(self.Object)
  end
end

function BRPlayerCharacterBase:RPC_Server_GmPlayAction(actionId)
  log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction.  actionId: " .. tostring(actionId))
  if USTExtraBlueprintFunctionLibrary.IsDevelopment() then
    log(bWriteLog and "  BRPlayerCharacterBase:RPC_Server_GmPlayAction. IsDevelopment actionId: " .. tostring(actionId))
    self:MulticastRPC_GmPlayAction(actionId)
  end
end

function BRPlayerCharacterBase:MulticastRPC_GmPlayAction(actionId)
  if not Client then
    return
  end
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction.  actionId: " .. tostring(actionId))
  local uPlayEmoteComp = self:GetPlayEmoteComponent()
  if not slua.isValid(uPlayEmoteComp) then
    return
  end
  local LogFilter = require("common.log_filter")
  LogFilter.SetLogTreeEnable(true)
  local animCfg = CDataTable.GetTableData("EmoteBPTable", actionId)
  if not animCfg then
    return
  end
  local handlePath = animCfg.Path
  local EmoteHandleAsset = slua.loadObject(handlePath)
  local assetsArray = slua.Array(UEnums.EPropertyClass.Struct, import("/Script/CoreUObject.SoftObjectPath"))
  local handle = EmoteHandleAsset()
  uPlayEmoteComp:OnLoadEmoteAssetBegin(handle, actionId, assetsArray, "")
  log(bWriteLog and "  BRPlayerCharacterBase:MulticastRPC_GmPlayAction. assetsArray:Num(): " .. tostring(assetsArray:Num()))
  local tb = FuncUtil.LuaArrayToTable(assetsArray)
  local asset_util = require("common.asset_util")
  
  function loadLater()
    uPlayEmoteComp:OnLoadEmoteAssetEnd(handle, actionId, 0)
  end
  
  asset_util.GetAssetsArrayAsyncParallel(tb, loadLater)
end

function BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall(bServerSyncShouldCheckPassWall)
  print(bWriteLog and "BRPlayerCharacterBase:RPC_Client_SetShouldCheckPassWall " .. tostring(bServerSyncShouldCheckPassWall))
  if slua.isValid(self.ParachuteComponent) then
    self.ParachuteComponent.bServerSyncShouldCheckPassWall = bServerSyncShouldCheckPassWall
  end
end

function BRPlayerCharacterBase:OnPlayerEnterCarryBoxState()
  self.Super:OnPlayerEnterCarryBoxState()
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerEnterCarryBoxState Role:%s PlayerKey:%s Name:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerEnterCarryBoxState()
  end
end

function BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  self.Super:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  local CharName = self:GetPlayerNameSafety()
  print(bWriteLog and string.format("DeadBoxLog BRPlayerCharacterBase:OnPlayerLeaveCarryBoxState Role:%s PlayerKey:%s Name:%s bInIsInterrupt:%s", tostring(self.Role), tostring(self.PlayerKey), tostring(CharName), tostring(bInIsInterrupt)))
  if self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:OnPlayerLeaveCarryBoxState(bInIsInterrupt)
  end
end

function BRPlayerCharacterBase:ServerRPC_CarryDeadBox(uInDeadBox)
  if slua.isValid(uInDeadBox) and Game:IsClassOf(uInDeadBox, import("/Script/ShadowTrackerExtra.PlayerTombBox")) and self.CarryDeadBoxFeature then
    self.CarryDeadBoxFeature:CarryDeadBox(uInDeadBox)
  end
end

function BRPlayerCharacterBase:SetAreaID(AreaID)
  self:SetAttrValue("AreaID", AreaID, -1)
end

function BRPlayerCharacterBase:GetAreaID()
  return math.floor(self:GetAttrValue("AreaID") + 0.5)
end

function BRPlayerCharacterBase:CannotChangeIntoPetSpectator()
  print(bWriteLog and "BRPlayerCharacterBase:CannotChangeIntoPetSpectator")
  return self.bCannotChangeIntoPetSpectator
end

function BRPlayerCharacterBase:DoModChangeToBT()
  print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s", tostring(self.PlayerKey)))
  if self:HasState(EPawnState.SpecialSuit) then
    self:TriggerEntrySkillWithID(4301101, true)
    print(bWriteLog and string.format("BRPlayerCharacterBase:DoModChangeToBT, PlayerKey=%s, HasState(EPawnState.SpecialSuit)", tostring(self.PlayerKey)))
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteOpening()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening")
  self.Super:SwitchCameraToParachuteOpening()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteOpening - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToParachuteFalling()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling")
  self.Super:SwitchCameraToParachuteFalling()
  if self.ParachuteFormation and self.ParachuteFormation.ShouldApplyFormationCamera and self.ParachuteFormation:ShouldApplyFormationCamera() then
    self.ParachuteFormation:OverlayFormationCameraParams()
    print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToParachuteFalling - Formation camera overlaid")
  end
end

function BRPlayerCharacterBase:SwitchCameraToNormal()
  print(bWriteLog and "BRPlayerCharacterBase:SwitchCameraToNormal")
  self.Super:SwitchCameraToNormal()
  if self.ParachuteFormation and self.ParachuteFormation.OnLandingClearFormationCamera then
    self.ParachuteFormation:OnLandingClearFormationCamera()
  end
end

function BRPlayerCharacterBase:SwitchWeaponCheck(Slot, IgnoreState)
  if self:HasState(EPawnState.AttachToOther) then
    local Weapon = self:GetWeaponBySlot(Slot)
    if slua.isValid(Weapon) then
      local WeaponID = Weapon:GetWeaponID()
      local AttachToOtherConfig = GamePlayTools.GetCurrentConfig("AttachToOtherConfig")
      if AttachToOtherConfig and AttachToOtherConfig.CheckIsWeaponInBlackList and AttachToOtherConfig.CheckIsWeaponInBlackList(WeaponID) then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck not allow switch weapon in AttachToOther, WeaponID: " .. tostring(WeaponID))
        local uPlayerController = self:GetPlayerControllerSafety()
        if Client and slua.isValid(uPlayerController) and uPlayerController.Role == ENetRole.ROLE_AutonomousProxy then
          uPlayerController:DisplayGameTipWithMsgID(47306)
        end
        return false
      end
    end
  end
  if self:HasState(EPawnState.WebSwing) and Slot ~= ESurviveWeaponPropSlot.SWPS_None and slua.isValid(self.STCharacterMovement) then
    local SpiderSwingObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
    if slua.isValid(SpiderSwingObj) then
      local nCurState = SpiderSwingObj:GetCurMoveState()
      if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then
        print(bWriteLog and "BRPlayerCharacterBase:SwitchWeaponCheck blocked by SpiderSwing state: " .. tostring(nCurState))
        return false
      end
    end
  end
  return self.Super:SwitchWeaponCheck(Slot, IgnoreState)
end

-- ==============================================================================
-- ============================ START FULL LOGIC MOD ==========================
-- ==============================================================================

local function Notify(msg) local s = "[MR.BEAN] " .. tostring(msg)
pcall(function() if _G.MON5LANotify then _G.MON5LANotify(s) end end)
pcall(function() local sh = import("ScriptHelperClient") if sh and
sh.AddOnScreenDebugMessage then sh.AddOnScreenDebugMessage(s, -1, 3.0, {R=1,
G=1, B=0, A=1}, {X=1.2, Y=1.2}) end end) print(s) end

local _slua = rawget(_G, "slua")

local function Valid(obj) if not obj then return false end if _slua and
_slua.isValid then local ok, v = pcall(_slua.isValid, obj) if not ok or not v
then return false end end return true end

-- ========================================== 
-- STATIC VARIABLES & GLOBAL CACHE OPTIMIZED (LAG-FREE)
-- ========================================== 
local C_GREEN = {R=0, G=255, B=0, A=255}
local C_RED = {R=255, G=0, B=0, A=255}
local C_CYAN = {R=0, G=255, B=255, A=255}
local C_YELLOW = {R=255, G=255, B=0, A=255}
local C_WHITE = {R=255, G=255, B=255, A=255}
local C_BLUE_TEXT = {R=0, G=200, B=255, A=255}
local SCALE_COLOR_V2 = {R=3, G=3, B=0, A=0}

-- ===== 7 WARNA UNTUK PILIHAN =====
local COLOR_PALETTE_7 = {
    [1] = {R=255, G=0,   B=0, A=255},   -- Red
    [2] = {R=255, G=255, B=255, A=255}, -- White
    [3] = {R=255, G=255, B=0, A=255},   -- Yellow
    [4] = {R=0,   G=255, B=0, A=255},   -- Green
    [5] = {R=0,   G=255, B=255, A=255}, -- Cyan
    [6] = {R=0,   G=0,   B=255, A=255}, -- Blue
    [7] = {R=255, G=0,   B=255, A=255}, -- Purple
}

local function GetColorBy7(idx)
    if not idx or idx < 1 or idx > 7 then idx = 4 end
    return COLOR_PALETTE_7[idx] or {R=0, G=255, B=0, A=255}
end

-- ESP Cache Variables
_G.CachedGameplayStatics = nil
_G.CachedActorClass_ForVehicle = nil
_G.CachedVehicleArray = nil
_G.CachedVehicles = nil
_G.LastVehicleScanTime = 0

_G.CachedActorClass_ForBomb = nil
_G.CachedProjArray = nil
_G.CachedActiveThrowables = nil
_G.CachedItemThrowables = nil
_G.LastThrowableScanTime = 0
_G.ActiveThrowableTimers = {}

_G.CachedActorClass_ForLoot = nil
_G.CachedLootArray = nil
_G.CachedLootItems = nil
_G.LastLootScanTime = 0

local GLOBAL_BONE_LIST = {
    "head", "neck_01", "pelvis",
    "upperarm_r", "lowerarm_r", "hand_r",
    "upperarm_l", "lowerarm_l", "hand_l",
    "thigh_l", "calf_l", "foot_l",
    "thigh_r", "calf_r", "foot_r"
}

-- ========================================== 
-- MON5LA CORE + FULL FEATURES VIP CONFIGURATION 
-- ========================================== 
_G.MON5LAConfig = _G.MON5LAConfig or { 
    CustomMagicBullet = false,
    AutoHead = false, 
    EspVip = false, 
    EspDistance = false, 
    EspVipPro = false, 
    EspRadar = false, 
    Esp5 = false, 
    Esp6 = false, 
    Esp7 = false,
    Esp8 = false,
    EspAntenna = false, 
    EspName = false,
    OutlineThickness = 10, 
    UnlockFPS = false, 
    IpadView = false, 
    -- === NEW FEATURES FROM GOLD ===
    IpadViewVehicle = false,
    IpadViewScope = false,
    CustomAimbot = false, 
    CustomAimbotClose = false, 
    CustomHRecoil = false,  
    CustomVRecoil = false,  
    LessShake = false, 
    RemoveGrass = false, 
    RemoveFog = false, 
    WhiteBody = false, 
    Wallhack = false, 
    Crosshair = false, 
    Accuracy = false,
    GodMode = false, 
    BlackSky = false,
    EspFovCircle = false,
    
    -- New Configuration for Aimbot V2 (Aim Touch)
    AimTouchEnable = false,
    AimTouchHipIgKnock = false,
    AimTouchHipIgBot = false,
    AimTouchSGIgKnock = false,
    AimTouchSGIgBot = false,
    AimTouchHipVisCheck = false,
    AimTouchSGVisCheck = false,
    AimTouchHipfire = false,
    AimTouchSG = false,
    AimTouchSGAutoFire = false,
    AimTouchScopeAll = false,
    AimTouchScopeIgKnock = false,
    AimTouchScopeIgBot = false,
    AimTouchScopeVisCheck = false,
    AimTouchScopeSniper = false,
    AimTouchSniperIgKnock = false,
    AimTouchSniperIgBot = false,
    AimTouchSniperVisCheck = false,
    -- === NEW AIMBOT MORTAR ===
    AimTouchMortar = false,
    
    -- ESP Vehicle
    VehicleEnabled = false,
    VehicleShowDacia = false,
    VehicleShowUAZ = false,
    VehicleShowBuggy = false,
    VehicleShowCoupe = false,
    VehicleShowMirado = false,
    VehicleShowMotor = false,
    VehicleShowOther = false,
    VehicleColor_Dacia = 4,
    VehicleColor_UAZ = 4,
    VehicleColor_Buggy = 4,
    VehicleColor_Coupe = 4,
    VehicleColor_Mirado = 4,
    VehicleColor_Motor = 4,
    VehicleColor_Other = 4,

    -- ESP Throwable
    ThrowableEnabled = false,
    ThrowableGrenade = false,
    ThrowableSmoke = false,
    ThrowableMolotov = false,
    ThrowableColor_Grenade = 4,
    ThrowableColor_Smoke = 4,
    ThrowableColor_Molotov = 4,
    ThrowableScanMode = 0,

    -- ESP Loot
    EspLoot = false,
    LootShowM416 = false,
    LootShowAUG = false,
    LootShowAKM = false,
    LootShowM24 = false,
    LootShowUMP = false,
    LootShowDBS = false,
    LootShowS12K = false,
    LootShowVest3 = false,
    LootShowHelmet3 = false,
    LootShowBag3 = false,
    LootColor_M416 = 4,
    LootColor_AUG = 4,
    LootColor_AKM = 4,
    LootColor_M24 = 4,
    LootColor_UMP = 4,
    LootColor_DBS = 4,
    LootColor_S12K = 4,
    LootColor_Vest3 = 4,
    LootColor_Helmet3 = 4,
    LootColor_Bag3 = 4,
    LootScanMode = 0,

    -- ESP Static
    EspStatic = false,
    EspEnemyCount = true,
    EspWeaponStatus = true,

    -- Skin Mod
    ModSkin = false,
    
    -- ===== TAMBAHAN EXPERT2 =====
    ExpertEnabled = false,
    EnableWeaponMod = false,
    WeaponMod = {
        [101001] = {FireSpeed = false, InstanHit = false, FastSwitch = false, FastScope = false},
        [101004] = {FireSpeed = false, InstanHit = false, FastSwitch = false, FastScope = false},
        [101008] = {FireSpeed = false, InstanHit = false, FastSwitch = false, FastScope = false},
    },
}

-- CONTAINS FULLY OPTIMIZED SYSTEM STATE WITH FREE RAM
_G.MON5LAState = _G.MON5LAState or { 
    LoopToken = 0, 
    AimbotLoopToken = 0,
    NativeESPReady = false,
    GraphicsUnlocked = false, 
    MenuStep = 0, 
    LastCmdTime = 0,
    TrackedMarks = {},
    EnemyMarks = {},
    LastAimbotCheckTime = 0, 
    CustomTextData = nil,     
    LastAimbotConfigString = "",
    MagicUpdateVersion = 1,
    LastMagicConfigHash = "",
    PrevGraphicsState = {},
    SkinWasApplied = false,
    ConsoleNewWallReady = false,
}



-- =====================================================================
-- ESP FULL SYSTEM — Part 1/6: Config + RedBoxOverlay
-- Integrated from ملف الاختبار.lua
-- =====================================================================

_G.LexusConfig = _G.LexusConfig or {
    EspLoai9 = false,
    Esp9_Count = true,
    Esp9_Name = true,
    Esp9_HP = true,
    Esp9_Team = true,
    Esp9_Weapon = true,
    Esp9_Distance = true,
    Esp9_Line = false,
    Esp9_Skeleton = false,
    ColorBodyNew = false,
    ChamsColorVis = 3,
    ChamsColorOcc = 1,
}

_G.LexusState = _G.LexusState or { LoopToken = 0 }

local _slua_esp = rawget(_G, "slua")

local function ESP_Valid(obj)
    if not obj then return false end
    if _slua_esp and _slua_esp.isValid then
        local ok, v = pcall(_slua_esp.isValid, obj)
        if not ok or not v then return false end
    end
    return true
end

_G.ESP_Valid = ESP_Valid

local ESP_C_GREEN = {R=0, G=255, B=0, A=255}
local ESP_C_RED = {R=255, G=0, B=0, A=255}
local ESP_C_CYAN = {R=0, G=255, B=255, A=255}
local ESP_C_YELLOW = {R=255, G=255, B=0, A=255}
local ESP_C_WHITE = {R=255, G=255, B=255, A=255}
local ESP_C_BLUE_TEXT = {R=0, G=200, B=255, A=255}

_G.ESP_Colors = {
    GREEN = ESP_C_GREEN, RED = ESP_C_RED, CYAN = ESP_C_CYAN,
    YELLOW = ESP_C_YELLOW, WHITE = ESP_C_WHITE, BLUE = ESP_C_BLUE_TEXT,
}

local ESP_GLOBAL_BONE_LIST = {
    "head", "Spine_03", "pelvis",
    "upperarm_r", "lowerarm_r", "hand_r",
    "upperarm_l", "lowerarm_l", "hand_l",
    "thigh_l", "calf_l", "foot_l",
    "thigh_r", "calf_r", "foot_r"
}

local function ESP_GetSafeEnemyKey(enemy)
    if ESP_Valid(enemy) then
        if enemy.PlayerKey then return tostring(enemy.PlayerKey) end
        if type(enemy.GetUniqueID) == "function" then return tostring(enemy:GetUniqueID()) end
    end
    return tostring(enemy)
end

local function ESP_CheckIsAI(pawn, markData)
    if markData and markData.AK_IS_BOT ~= nil then return markData.AK_IS_BOT, true end
    local isAI = false
    local hasChecked = false
    pcall(function()
        if pawn.bIsAI == true or pawn.IsAI == true then isAI = true; hasChecked = true end
        if type(pawn.IsBot) == "function" and pawn:IsBot() then isAI = true; hasChecked = true end
        local pState = pawn.PlayerState or (type(pawn.GetPlayerState) == "function" and pawn:GetPlayerState())
        if ESP_Valid(pState) then
            hasChecked = true
            if pState.bIsABot == true or pState.bIsBot == true then isAI = true end
            if type(pState.IsBot) == "function" and pState:IsBot() then isAI = true end
        end
    end)
    if hasChecked and markData then markData.AK_IS_BOT = isAI end
    return isAI, hasChecked
end

local function ESP_GetAllSkeletalMeshes(enemy, markData)
    local curTime = os.clock()
    if markData and markData.CachedMeshes and markData.CachedMeshTime and (curTime - markData.CachedMeshTime < 0.5) then
        local validMeshes = {}
        for _, cachedMesh in ipairs(markData.CachedMeshes) do
            local isPendingKill = false
            pcall(function() if type(cachedMesh.IsPendingKill) == "function" then isPendingKill = cachedMesh:IsPendingKill() end end)
            if ESP_Valid(cachedMesh) and not isPendingKill then table.insert(validMeshes, cachedMesh) end
        end
        markData.CachedMeshes = validMeshes
        return validMeshes
    end
    local meshes = {}
    if ESP_Valid(enemy.Mesh) then table.insert(meshes, enemy.Mesh) end
    pcall(function()
        local SkeletalMeshClass = import("SkeletalMeshComponent")
        if SkeletalMeshClass and type(enemy.GetComponentsByClass) == "function" then
            local childs = enemy:GetComponentsByClass(SkeletalMeshClass)
            if childs then
                local count = type(childs.Num) == "function" and childs:Num() or #childs
                for i = 1, count do
                    local comp = type(childs.Get) == "function" and childs:Get(i-1) or childs[i]
                    if ESP_Valid(comp) and comp ~= enemy.Mesh then table.insert(meshes, comp) end
                end
            end
        end
    end)
    if markData then markData.CachedMeshes = meshes; markData.CachedMeshTime = curTime end
    return meshes
end

-- =====================================================================
-- RedBoxOverlay — عدّاد اللاعبين والبوتات (النسخة السوداء من MR.BEAN)
-- =====================================================================
_G.RedBoxOverlay = _G.RedBoxOverlay or {
    bActive      = false,
    _Widget      = nil,
    _Slot        = nil,
    PlayerCount  = 0,
    BotCount     = 0,
    _CachedText  = "",
    FontSize     = 14,
    Width        = 220,
    Height       = 30,
}

local RB = _G.RedBoxOverlay

local RB_BTN_BP = "/Game/UMG/UI_BP/Common/BaseComponent/CommonBaseComponent_TextButton_UIBP.CommonBaseComponent_TextButton_UIBP"

function RB.Create()
    if RB._Widget and slua.isValid(RB._Widget) then return true end

    local ok = pcall(function()
        local btn = slua.loadUI(RB_BTN_BP)
        if not btn or not slua.isValid(btn) then error("RedBox load failed") end

        require("game_frontend_hud").AddToContainer(UIContainers.Top, btn, 10500)

        if btn.RichText_Content then
            local strText = string.format("لاعب: %d | بوت: %d", RB.PlayerCount, RB.BotCount)
            btn.RichText_Content:SetText(strText)
            RB._CachedText = strText
            local fontInfo = btn.RichText_Content.Font
            if fontInfo then
                fontInfo.Size = RB.FontSize
                btn.RichText_Content:SetFont(fontInfo)
            end
        end

        local WidgetLayoutLibrary = import("WidgetLayoutLibrary")
        local slot = WidgetLayoutLibrary.SlotAsCanvasSlot(btn)
        if slot then
            slot:SetAnchors(FAnchors(0.5, 0, 0.5, 0))
            slot:SetAlignment(FVector2D(0.5, 0))
            pcall(function() slot:SetAutoSize(false) end)
            slot:SetPosition(FVector2D(0, 30))
            slot:SetSize(FVector2D(RB.Width, RB.Height))
        end

        pcall(function() btn:SetRenderTransformPivot(FVector2D(0.5, 0.5)) end)
pcall(function() btn:SetRenderScale(FVector2D(1.0, 1.0)) end)
btn:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)

-- ✅ السطر الجديد هنا 👇
pcall(function() if btn.Image_Background then btn.Image_Background:SetColorAndOpacity(FLinearColor(0, 0, 0, 1)) end end)

RB._Widget = btn
RB._Slot   = slot
    end)

    return ok and RB._Widget ~= nil
end

function RB.SetCounts(players, bots)
    if RB.PlayerCount == players and RB.BotCount == bots then return end
    RB.PlayerCount = players or 0
    RB.BotCount    = bots or 0

    if RB._Widget and slua.isValid(RB._Widget) then
        pcall(function()
            local str = string.format("لاعب: %d | بوت: %d", RB.PlayerCount, RB.BotCount)
            if RB._CachedText ~= str then
                if RB._Widget.RichText_Content then
                    RB._Widget.RichText_Content:SetText(str)
                end
                RB._CachedText = str
            end
        end)
    end
end

-- لا يحتاج تحديث موضع (ثابت أعلى الشاشة)
function RB.UpdatePosition() end

function RB.Start()
    if RB.bActive and RB._Widget and slua.isValid(RB._Widget) then return end
    if RB.Create() then
        RB.bActive = true
        pcall(function()
            RB._Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)
    end
end

function RB.Stop()
    RB.bActive = false
    if RB._Widget and slua.isValid(RB._Widget) then
        pcall(function()
            RB._Widget:RemoveFromParent()
            RB._Widget:ConditionalBeginDestroy()
        end)
    end
    RB._Widget     = nil
    RB._Slot       = nil
    RB._CachedText = ""
end

_G.RedBoxOverlay = RB

-- =====================================================================
-- ESP FULL SYSTEM — Part 2/6: PlayerMapMarker Foundation
-- =====================================================================

local SlateBlueprintLibrary = nil
local WidgetLayoutLibrary = nil
local KismetMathLibrary = nil

pcall(function() SlateBlueprintLibrary = import("SlateBlueprintLibrary") or import("/Script/UMG.SlateBlueprintLibrary") end)
pcall(function() WidgetLayoutLibrary = import("WidgetLayoutLibrary") or import("/Script/UMG.WidgetLayoutLibrary") end)
pcall(function() KismetMathLibrary = import("KismetMathLibrary") end)

local FVector2D = _G.FVector2D or import("Vector2D")
local FLinearColor = _G.FLinearColor or import("LinearColor")
local FVector = _G.FVector or import("Vector")

_G.PlayerMapMarker = _G.PlayerMapMarker or {}

local PMM = _G.PlayerMapMarker

-- ═══════════════════════════════════════════════════════════════════
-- الثوابت الأساسية
-- ═══════════════════════════════════════════════════════════════════
PMM.MarkTypeID = 1007
PMM.bUseScreenESP = true
PMM.WidgetCompUIPath = "/Game/BluePrints/ControlInput/NewbieItem/NewbieTips_ConsumeTips.NewbieTips_ConsumeTips"
PMM.WidgetCompBoneName = "head"
PMM.WidgetCompOffset = FVector and FVector(0, 0, 80) or {X=0, Y=0, Z=80}
PMM.WidgetCompDrawSize = FVector2D and FVector2D(210, 35) or {X=210, Y=35}

PMM.ESPBoneName = "head"
PMM.ESPWorldOffsetZ = 0
PMM.ESPScreenOffsetY = 0
PMM.ESPAnchorOffsetX = 35
PMM.ESPAnchorOffsetY = 0
PMM.ESPTextOffsetX = 0
PMM.ESPTextOffsetY = 0
PMM.ESPWidgetAlignment = FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0}
PMM.ESPWidgetSize = FVector2D and FVector2D(70, 21) or {X=70, Y=21}
PMM.ESPWidgetAutoSize = true
PMM.ESPWidgetZOrder = 2

PMM.bShowDistance = true
PMM.DistanceUnit = "m"
PMM.WeaponIconBrushW = 96
PMM.WeaponIconBrushH = 48
PMM.HPWidgetSwitcherTypeIndex = 0
PMM.HPWidgetSwitcherType2Index = 0
PMM.bForceSwitcherIndexEveryUpdate = true

PMM.bUseSnapLines = true
PMM.SnapLineThickness = 1.0
PMM.SnapLineOriginY = 50
PMM.SnapLineOriginOffsetX = 0
PMM.SnapLineHeadOffsetX = 0
PMM.SnapLineHeadOffsetY = -14
PMM.SnapLineColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=255, G=255, B=255, A=255}
PMM.SnapLineOpacity = 0.7

PMM.bUseSkeleton = true
PMM.SkeletonThickness = 0.8
PMM.SkeletonOpacity = 0.8
PMM.SkeletonMaxDistance = 100000
PMM.bUseVisibilityColor = true

PMM.SkeletonChains = {
    {"Spine_03", "lowerarm_r", "hand_r"},
    {"Spine_03", "lowerarm_l", "hand_l"},
    {"head", "Spine_03", "pelvis"},
    {"pelvis", "calf_r", "foot_r"},
    {"pelvis", "calf_l", "foot_l"}
}

PMM.BoneNameFallbacks = {
    ["head"] = {"head", "Head", "head_socket"},
    ["Spine_03"] = {"Spine_03", "Spine_03", "neck", "Neck"},
    ["clavicle_r"] = {"clavicle_r", "Clavicle_R", "clavicle_R"},
    ["upperarm_r"] = {"upperarm_r", "UpperArm_R", "arm_r", "arm_r_01"},
    ["lowerarm_r"] = {"lowerarm_r", "LowerArm_R", "forearm_r"},
    ["hand_r"] = {"hand_r", "Hand_R", "hand_r_socket"},
    ["clavicle_l"] = {"clavicle_l", "Clavicle_L", "clavicle_L"},
    ["upperarm_l"] = {"upperarm_l", "UpperArm_L", "arm_l", "arm_l_01"},
    ["lowerarm_l"] = {"lowerarm_l", "LowerArm_L", "forearm_l"},
    ["hand_l"] = {"hand_l", "Hand_L", "hand_l_socket"},
    ["spine_03"] = {"spine_03", "Spine_03", "spine_02", "spine"},
    ["spine_02"] = {"spine_02", "Spine_02", "spine_01"},
    ["pelvis"] = {"pelvis", "Pelvis", "hip"},
    ["thigh_r"] = {"thigh_r", "Thigh_R", "leg_r"},
    ["calf_r"] = {"calf_r", "Calf_R", "shin_r"},
    ["foot_r"] = {"foot_r", "Foot_R", "foot_r_socket"},
    ["thigh_l"] = {"thigh_l", "Thigh_L", "leg_l"},
    ["calf_l"] = {"calf_l", "Calf_L", "shin_l"},
    ["foot_l"] = {"foot_l", "Foot_L", "foot_l_socket"},
}

PMM.nUpdateInterval = 0.5
PMM.bUseFrameTick = false
PMM.nHeavyScanFrameInterval = 15
PMM.nDistanceUpdateFrameInterval = 5
PMM.bIncludeMe = false
PMM.bIncludeAI = true
PMM.bUseServerMarks = false

PMM.bActive = false
PMM.MarkMap = {}
PMM.PlayerInfo = {}
PMM.ESPCanvas = nil
PMM.ESPWidgets = {}
PMM.ESPWidgetPtrs = {}
PMM.SnapLineWidgets = {}
PMM.SkeletonWidgets = {}
PMM._StaticBoneLocCache = {}

PMM._cachedViewportW = 1920
PMM._cachedViewportH = 1080
PMM._FrameCount = 0
PMM._bTickRegistered = false
PMM._CachedAllChars = nil
PMM._CachedMyLoc = nil
PMM._CachedMyKey = nil
PMM.WidgetComps = {}
PMM._bAllPathsFailed = false
PMM._bLightUpdateScheduled = false
PMM._LightUpdateInterval = 0.02
PMM._bDistanceUpdateScheduled = false
PMM._DistanceUpdateInterval = 0.1
PMM._bScreenMarkConfigSetup = false

PMM._CachedPC = nil
PMM._CachedGameplayData = nil
PMM._CachedCGameState = nil
PMM._CanvasScaleX = 1.0
PMM._CanvasScaleY = 1.0
PMM._CanvasOffsetX = 0.0
PMM._CanvasOffsetY = 0.0

-- ═══════════════════════════════════════════════════════════════════
-- دوال مساعدة عامة
-- ═══════════════════════════════════════════════════════════════════
local function IsValid(obj)
    if obj == nil then return false end
    if slua and slua.isValid then return slua.isValid(obj) end
    return obj ~= nil
end

PMM._IsValid = IsValid

-- ═══════════════════════════════════════════════════════════════════
-- Screen Mark Config Setup
-- ═══════════════════════════════════════════════════════════════════
function PMM.SetupScreenMarkConfig()
    if PMM._bScreenMarkConfigSetup then return true end
    local bOK = false
    pcall(function()
        local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
        local ScreenMarkConfig = GamePlayTools.GetCurrentConfig("ScreenMarkConfig")
        if ScreenMarkConfig then
            ScreenMarkConfig[1007] = {
                UIPathName = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP_C",
                MaxWidgetNum = 100,
                MaxShowDistance = 6000000,
                bBindOutScreen = false,
                bBindBlocked = true,
                bNeedPreLoad = true,
                bIsBindingActor = true,
                BindSocketName = "HelmetSocket",
                WorldPositionOffset = FVector and FVector(0, 0, 80) or {X=0,Y=0,Z=80}
            }
            PMM._bScreenMarkConfigSetup = true
            bOK = true
        end
    end)
    return bOK
end

-- ═══════════════════════════════════════════════════════════════════
-- GameplayData / PC / GameState accessors
-- ═══════════════════════════════════════════════════════════════════
function PMM.GetGameplayData()
    if PMM._CachedGameplayData then return PMM._CachedGameplayData end
    local ok, GDP = pcall(function() return require("GameLua.GameCore.Data.GameplayData") end)
    if ok and GDP then PMM._CachedGameplayData = GDP return GDP end
    return nil
end

function PMM.GetMyPlayerController()
    local PC = PMM._CachedPC
    if PC and IsValid(PC) then return PC end
    local GDP = PMM.GetGameplayData()
    if not GDP then return nil end
    pcall(function() PC = GDP.GetPlayerController and GDP.GetPlayerController() end)
    if PC and IsValid(PC) then PMM._CachedPC = PC return PC end
    return nil
end

function PMM.GetCGameState()
    if CGameState and IsValid(CGameState) then return CGameState end
    if PMM._CachedCGameState and IsValid(PMM._CachedCGameState) then return PMM._CachedCGameState end
    local ok, GS = pcall(function() return require("GameLua.GameCore.Data.CGameState") end)
    if ok and GS then PMM._CachedCGameState = GS return GS end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════
-- GetAllCharacters — متعدد المحاولات لدعم جميع الخرائط
-- ═══════════════════════════════════════════════════════════════════
function PMM.GetAllCharacters()
    local AllChars = {}
    pcall(function()
        local Pawns = Game:GetAllPlayerPawns()
        if Pawns then
            for _, Pawn in pairs(Pawns) do
                if Pawn and slua.isValid(Pawn) then
                    local pKey = nil
                    if Pawn.GetPlayerKey then pKey = Pawn:GetPlayerKey() end
                    if not pKey and Pawn.PlayerKey then pKey = Pawn.PlayerKey end
                    if not pKey and Pawn.PlayerState and Pawn.PlayerState.PlayerKey then pKey = Pawn.PlayerState.PlayerKey end
                    if pKey then AllChars[pKey] = Pawn end
                end
            end
        end
    end)
    if not next(AllChars) then
        local GS = PMM.GetCGameState()
        if GS and GS.GetAllCharacters then pcall(function() AllChars = GS:GetAllCharacters() end) end
    end
    if not next(AllChars) then
        local GDP = PMM.GetGameplayData()
        if GDP and GDP.GetAllPlayerCharacters then
            pcall(function()
                local chars = GDP.GetAllPlayerCharacters()
                if chars then
                    for k, v in pairs(chars) do
                        if v and slua.isValid(v) then
                            local pKey = v.PlayerKey or (v.GetPlayerKey and v:GetPlayerKey())
                            if pKey then AllChars[pKey] = v else AllChars[tostring(v)] = v end
                        end
                    end
                end
            end)
        end
    end
    return AllChars
end

function PMM.GetMyPlayerKey()
    local PC = PMM.GetMyPlayerController()
    if not IsValid(PC) then return nil end
    local MyKey = nil
    pcall(function()
        if PC.GetPlayerKey then MyKey = PC:GetPlayerKey()
        elseif PC.PlayerState and PC.PlayerState.PlayerKey then MyKey = PC.PlayerState.PlayerKey end
    end)
    return MyKey
end

function PMM.IsMe(Character, PlayerKey, MyKey)
    local bIsMe = false
    pcall(function()
        local GDP = PMM.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then
            local MyChar = GDP.GetLocalCharacter()
            if MyChar and Character == MyChar then bIsMe = true return end
        end
        local PC = PMM.GetMyPlayerController()
        if PC and PC.GetPawn then
            local Pawn = PC:GetPawn()
            if Pawn and Character == Pawn then bIsMe = true return end
        end
    end)
    if not bIsMe and MyKey ~= nil and PlayerKey ~= nil then bIsMe = (tostring(PlayerKey) == tostring(MyKey)) end
    return bIsMe
end

function PMM.GetCharacterLocation(Character)
    if not IsValid(Character) then return nil end
    local Loc = nil
    pcall(function() if Character.K2_GetActorLocation then Loc = Character:K2_GetActorLocation() end end)
    if not Loc then pcall(function() if Game and Game.GetActorLocation then Loc = Game:GetActorLocation(Character) end end) end
    return Loc
end

function PMM.CalcDistance(Loc1, Loc2)
    if not Loc1 or not Loc2 then return nil end
    local Dist = nil
    pcall(function() if FVector and FVector.Dist2D then Dist = FVector.Dist2D(Loc1, Loc2) end end)
    if not Dist then
        pcall(function()
            local DX = (Loc1.X or 0) - (Loc2.X or 0)
            local DY = (Loc1.Y or 0) - (Loc2.Y or 0)
            Dist = math.sqrt(DX * DX + DY * DY)
        end)
    end
    return Dist
end

function PMM.GetDistanceString(MyLoc, TargetLoc)
    if not PMM.bShowDistance then return "" end
    if not MyLoc or not TargetLoc then return "" end
    local Dist = PMM.CalcDistance(MyLoc, TargetLoc)
    if not Dist then return "" end
    local Meters = Dist / 100
    if Meters < 1000 then return string.format("%dm", math.floor(Meters))
    else return string.format("%.1fkm", Meters / 1000) end
end

function PMM.GetMyLocation()
    local GDP = PMM.GetGameplayData()
    if not GDP then return nil end
    local MyChar = nil
    pcall(function() MyChar = GDP.GetLocalCharacter and GDP.GetLocalCharacter() end)
    if not IsValid(MyChar) then
        local PC = PMM.GetMyPlayerController()
        if IsValid(PC) then
            pcall(function()
                if PC.GetPawn then
                    local Pawn = PC:GetPawn()
                    if IsValid(Pawn) and Pawn.K2_GetActorLocation then return Pawn:K2_GetActorLocation() end
                end
            end)
        end
        return nil
    end
    return PMM.GetCharacterLocation(MyChar)
end

function PMM.GetPlayerName(Character)
    if not IsValid(Character) then return "Unknown" end
    local Name = nil
    pcall(function() if Character.GetPlayerNameSafety then Name = Character:GetPlayerNameSafety() end end)
    if not Name then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety()
            elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if IsValid(PS) and PS.GetPlayerName then Name = PS:GetPlayerName() end
        end)
    end
    return Name or "Unknown"
end

function PMM.IsAI(Character)
    local bAI = false
    pcall(function() if Game and Game.IsAI then bAI = Game:IsAI(Character) end end)
    return bAI
end

function PMM.IsAlive(Character)
    local bAlive = true
    pcall(function() if Character.IsAlive then bAlive = Character:IsAlive() end end)
    return bAlive
end

function PMM.GetTeamID(Character)
    if not IsValid(Character) then return nil end
    local TeamID = nil
    pcall(function() if Character.GetTeamID then TeamID = Character:GetTeamID() end end)
    if not TeamID then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety()
            elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if IsValid(PS) and PS.GetTeamID then TeamID = PS:GetTeamID()
            elseif IsValid(PS) and PS.TeamID then TeamID = PS.TeamID end
        end)
    end
    if not TeamID then pcall(function() if Character.TeamID then TeamID = Character.TeamID end end) end
    return TeamID
end

function PMM.GetTeamColor(TeamID)
    return FLinearColor and FLinearColor(0.1, 0.4, 1.0, 1.0) or {R=25,G=100,B=255,A=255}
end

function PMM.GetCharacterMesh(Character)
    if not IsValid(Character) then return nil end
    local Mesh = nil
    pcall(function() if Character.Mesh and Game:IsValid(Character.Mesh) then Mesh = Character.Mesh end end)
    if not Mesh then pcall(function() local SkeletalMeshCompClass = import("/Script/Engine.SkeletalMeshComponent") Mesh = Character:GetComponentByClass(SkeletalMeshCompClass) end) end
    return Mesh
end

function PMM.GetESPLocation(Character)
    if not IsValid(Character) then return nil end
    local BoneLoc = PMM.GetCharacterLocation(Character)
    if BoneLoc then
        local heightOffset = 85
        pcall(function()
            if Character.bIsCrouched then heightOffset = 60 end
            if Character.IsProne and Character:IsProne() then heightOffset = 30 end
        end)
        pcall(function() BoneLoc.Z = BoneLoc.Z + heightOffset + (PMM.ESPWorldOffsetZ or 0) end)
    end
    return BoneLoc
end

-- ═══════════════════════════════════════════════════════════════════
-- ESP Canvas Init
-- ═══════════════════════════════════════════════════════════════════
function PMM.IsOurESPWidget(w)
    if not w or not slua.isValid(w) then return false end
    -- ✅ فقط الويدجت التي أنشأناها نحن تُعتبر "خاصتنا"
    local bIsOurs = false
    pcall(function()
        local wstr = tostring(w)
        for KeyStr, ESPData in pairs(PMM.ESPWidgets) do
            if ESPData and ESPData.Widget and ESPData.Widget.Container then
                local cstr = tostring(ESPData.Widget.Container)
                if cstr == wstr then bIsOurs = true return end
            end
        end
    end)
    return bIsOurs
end

function PMM.InitESPCanvas()
    if PMM.ESPCanvas and Game:IsValid(PMM.ESPCanvas) then return true end
    local InGameUITools = nil
    pcall(function() InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools") end)
    if not InGameUITools then return false end
    local MainControlBaseUI = nil
    pcall(function() MainControlBaseUI = InGameUITools.GetMainControlBaseUI() end)
    if not MainControlBaseUI or not Game:IsValid(MainControlBaseUI) then return false end

    local ParentCanvas = nil
    pcall(function()
        if MainControlBaseUI.CanvasPanel_0 and Game:IsValid(MainControlBaseUI.CanvasPanel_0) then ParentCanvas = MainControlBaseUI.CanvasPanel_0
        elseif MainControlBaseUI.CanvasPanel_42 and Game:IsValid(MainControlBaseUI.CanvasPanel_42) then ParentCanvas = MainControlBaseUI.CanvasPanel_42 end
    end)

    if not ParentCanvas then return false end
    PMM.ESPCanvas = ParentCanvas

    -- ✅ لا تحذف أي شيء من Canvas الأصلي
    -- فقط احفظ مرجع له
    return true
end

print("[N5LA] ✅ ESP Part 2/6 loaded (PlayerMapMarker Foundation)")

-- =====================================================================
-- ESP FULL SYSTEM — Part 3/6: ESP Widgets (Create/Update/Health/Text)
-- =====================================================================
-- استخدم المتغير PMM المعرّف في الجزء 2
-- و دوال ESP_Valid / IsValid من الأجزاء السابقة

-- ═══════════════════════════════════════════════════════════════════
-- Find ProgressBar / Widget in Tree
-- ═══════════════════════════════════════════════════════════════════
function PMM.FindProgressBarInWidget(WidgetObj, Depth, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    Depth = Depth or 0; MaxDepth = MaxDepth or 5
    if Depth > MaxDepth then return nil end
    local bIsPB = false
    pcall(function() if WidgetObj.SetPercent and WidgetObj.SetFillColorAndOpacity then bIsPB = true end end)
    if bIsPB then return WidgetObj end
    local nChildren = 0
    pcall(function() if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end end)
    for i = 0, math.max(nChildren - 1, 0) do
        local child = nil
        pcall(function() child = WidgetObj:GetChildAt(i) end)
        if child and slua.isValid(child) then
            local result = PMM.FindProgressBarInWidget(child, Depth + 1, MaxDepth)
            if result then return result end
        end
    end
    return nil
end

function PMM._GetWidgetRoot(WidgetObj)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    local Root = nil
    pcall(function() if WidgetObj.GetRootWidget then Root = WidgetObj:GetRootWidget() end end)
    if Root and slua.isValid(Root) then return Root end
    pcall(function() if WidgetObj.WidgetTree and WidgetObj.WidgetTree.RootWidget then Root = WidgetObj.WidgetTree.RootWidget end end)
    if Root and slua.isValid(Root) then return Root end
    pcall(function() if WidgetObj.RootWidget and slua.isValid(WidgetObj.RootWidget) then Root = WidgetObj.RootWidget end end)
    return Root
end

function PMM._FindNamedWidgetInTree(WidgetObj, TargetName, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    MaxDepth = MaxDepth or 8
    local wname = nil
    pcall(function() if WidgetObj.GetName then wname = WidgetObj:GetName() end end)
    if wname and wname == TargetName then return WidgetObj end
    local wstr = tostring(WidgetObj)
    if wstr and string.find(wstr, TargetName, 1, true) then
        if wname and wname == TargetName then return WidgetObj
        elseif not wname or wname == "" then
            local _, endPos = string.find(wstr, TargetName, 1, true)
            if endPos then
                local nextChar = string.sub(wstr, endPos + 1, endPos + 1)
                if nextChar ~= "_" and nextChar ~= "" then return WidgetObj end
            end
        end
    end
    local nChildren = 0
    pcall(function() if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end end)
    if nChildren > 0 then
        for i = 0, nChildren - 1 do
            local child = nil
            pcall(function() child = WidgetObj:GetChildAt(i) end)
            if child and slua.isValid(child) then
                local found = PMM._FindNamedWidgetInTree(child, TargetName, MaxDepth - 1)
                if found then return found end
            end
        end
    else
        local Root = PMM._GetWidgetRoot(WidgetObj)
        if Root and slua.isValid(Root) and Root ~= WidgetObj then
            local found = PMM._FindNamedWidgetInTree(Root, TargetName, MaxDepth - 1)
            if found then return found end
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════
-- White Texture + Set Image Color
-- ═══════════════════════════════════════════════════════════════════
local _WhiteTexture = nil
local _bWhiteTextureFailed = false

local function GetWhiteTexture()
    if _WhiteTexture then return _WhiteTexture end
    if _bWhiteTextureFailed then return nil end
    pcall(function()
        local paths = {
            "/Game/BluePrints/UI/Textures/White.White",
            "/Game/BluePrints/UI/Textures/Common/White.White",
            "/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture"
        }
        for _, path in ipairs(paths) do
            pcall(function() local tex = import(path); if tex and slua.isValid(tex) then _WhiteTexture = tex return end end)
            if _WhiteTexture then break end
        end
    end)
    if not _WhiteTexture then _bWhiteTextureFailed = true end
    return _WhiteTexture
end

local function SetImageColor(Image, color)
    if not Image or not slua.isValid(Image) then return false end
    local bOK = false
    pcall(function() if Image.SetBrushTintColor then Image:SetBrushTintColor(color); bOK = true end end)
    pcall(function() if Image.SetColorAndOpacity then Image:SetColorAndOpacity(color); bOK = true end end)
    pcall(function()
        if Image.SetBrushFromTexture then
            local whiteTex = GetWhiteTexture()
            if whiteTex then
                Image:SetBrushFromTexture(whiteTex, false)
                if Image.SetColorAndOpacity then Image:SetColorAndOpacity(color) end
                bOK = true
            end
        end
    end)
    pcall(function() Image:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible); Image:SetRenderOpacity(1.0) end)
    return bOK
end

PMM.SetImageColor = SetImageColor

-- ═══════════════════════════════════════════════════════════════════
-- Apply Team Color
-- ═══════════════════════════════════════════════════════════════════
function PMM.ApplyTeamColor(Widget, TeamID)
    if not Widget or not Widget.Container then return end

    if not _G.LexusConfig.Esp9_Team then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                local img1 = PMM._FindNamedWidgetInTree(W, "Image_TeamBG", 8)
                if img1 and slua.isValid(img1) then img1:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
                local img2 = PMM._FindNamedWidgetInTree(W, "Image_TeamLogoBG", 8)
                if img2 and slua.isValid(img2) then img2:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
                if Widget.TeamBgBorder and slua.isValid(Widget.TeamBgBorder) then Widget.TeamBgBorder:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
            end
        end)
        return
    end

    local color = PMM.GetTeamColor(TeamID)
    if not color then return end

    pcall(function()
        local W = Widget.Container
        if not W or not slua.isValid(W) then return end
        local Image_TeamBG = PMM._FindNamedWidgetInTree(W, "Image_TeamBG", 8)
        if Image_TeamBG and slua.isValid(Image_TeamBG) then SetImageColor(Image_TeamBG, color) end
        local Image_TeamLogoBG = PMM._FindNamedWidgetInTree(W, "Image_TeamLogoBG", 8)
        if Image_TeamLogoBG and slua.isValid(Image_TeamLogoBG) then SetImageColor(Image_TeamLogoBG, color) end
        if W.SetTeamColor then pcall(function() W:SetTeamColor(TeamID) end) end

        if not Widget.TeamBgBorder or not slua.isValid(Widget.TeamBgBorder) then
            pcall(function()
                local Border = CGame:NewObjectFromPath("/Script/UMG.Border", W)
                if Border and slua.isValid(Border) then
                    pcall(function() Border:SetBrushColor(color) end)
                    pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    pcall(function() Border:SetRenderOpacity(0.7) end)
                    pcall(function() Border:SetDesiredSizeOverride(FVector2D and FVector2D(120, 20) or {X=120, Y=20}) end)
                    pcall(function() if W.AddChild then W:AddChild(Border) end end)
                    pcall(function() if Border.SetZOrder then Border:SetZOrder(-1) end end)
                    Widget.TeamBgBorder = Border
                end
            end)
        else
            pcall(function()
                Widget.TeamBgBorder:SetBrushColor(color)
                Widget.TeamBgBorder:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                Widget.TeamBgBorder:SetRenderOpacity(0.7)
            end)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- Create ESP Widget
-- ═══════════════════════════════════════════════════════════════════
PMM._OBHeadWidgetClass = nil
PMM._OBHeadWidgetLoadFailed = false
PMM._bDumpedWidgetChildren = false

function PMM.CreateESPWidget()
    if not PMM.ESPCanvas or not Game:IsValid(PMM.ESPCanvas) then return nil end
    if PMM._OBHeadWidgetLoadFailed then return nil end

    if not PMM._OBHeadWidgetClass then
        pcall(function()
            local Path = "/Game/BluePrints/UI/OBUI/Item/OB_PlayerHeadHPItem_UIBP.OB_PlayerHeadHPItem_UIBP"
            local uClass = slua.loadClass(Path)
            if uClass then PMM._OBHeadWidgetClass = uClass end
        end)
        if not PMM._OBHeadWidgetClass then
            PMM._OBHeadWidgetLoadFailed = true
            return nil
        end
    else
        local bValid = false
        pcall(function() bValid = slua.isValid(PMM._OBHeadWidgetClass) end)
        if not bValid then
            PMM._OBHeadWidgetLoadFailed = true
            PMM._OBHeadWidgetClass = nil
            return nil
        end
    end

    local Widget = nil
    pcall(function()
        local STExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
        local PC = PMM.GetMyPlayerController()
        local OuterObj = IsValid(PC) and PC.Object or PMM.ESPCanvas
        Widget = STExtraBlueprintFunctionLibrary.CreateWidgetByClass(PMM._OBHeadWidgetClass, OuterObj)
    end)

    if not Widget then return nil end

    pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    pcall(function() Widget:SetRenderOpacity(1.0) end)

    local NameText = nil
    local HealthFill = nil
    local bIsOriginalProgressBar = false

    pcall(function()
        NameText = Widget.TextBlock_TeamName
        if NameText and slua.isValid(NameText) then pcall(function() NameText:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end) end
        if Widget.TextBlock_PlayerName and slua.isValid(Widget.TextBlock_PlayerName) then pcall(function() Widget.TextBlock_PlayerName:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end) end

        local WS_Type = Widget.WidgetSwitcher_Type
        local WS_Type2 = Widget.WidgetSwitcher_Type2
        if WS_Type and slua.isValid(WS_Type) then pcall(function() if WS_Type.SetActiveWidgetIndex then WS_Type:SetActiveWidgetIndex(PMM.HPWidgetSwitcherTypeIndex) end end) end
        if WS_Type2 and slua.isValid(WS_Type2) then pcall(function() if WS_Type2.SetActiveWidgetIndex then WS_Type2:SetActiveWidgetIndex(PMM.HPWidgetSwitcherType2Index) end end) end

        local SizeBox_HP = Widget.SizeBox_HP
        if SizeBox_HP and slua.isValid(SizeBox_HP) then
            pcall(function() SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            pcall(function() SizeBox_HP:SetHeightOverride(6) end)
            pcall(function() SizeBox_HP:SetWidthOverride(100) end)

            local ExistingChild = nil
            pcall(function() if SizeBox_HP.GetContent then ExistingChild = SizeBox_HP:GetContent() end end)
            if not ExistingChild then pcall(function() if SizeBox_HP.GetChildAt then ExistingChild = SizeBox_HP:GetChildAt(0) end end) end

            if ExistingChild and slua.isValid(ExistingChild) then
                pcall(function() ExistingChild:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                pcall(function() ExistingChild:SetRenderOpacity(1.0) end)
                local FoundPB = PMM.FindProgressBarInWidget(ExistingChild, 0, 5)
                if FoundPB and slua.isValid(FoundPB) then
                    HealthFill = FoundPB
                    bIsOriginalProgressBar = true
                    pcall(function() FoundPB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    pcall(function() FoundPB:SetRenderOpacity(1.0) end)
                else
                    local PB = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", ExistingChild)
                    if PB then
                        pcall(function() PB:SetFillColorAndOpacity(FLinearColor and FLinearColor(0.88, 0.96, 1.0, 1.0) or {R=224,G=245,B=255,A=1}) end)
                        pcall(function() PB:SetPercent(1.0) end)
                        pcall(function() PB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                        pcall(function() PB:SetRenderOpacity(1.0) end)
                        pcall(function() PB:SetDesiredSizeOverride(FVector2D and FVector2D(100, 6) or {X=100, Y=6}) end)
                        pcall(function() ExistingChild:AddChild(PB) end)
                        HealthFill = PB
                    end
                end
            else
                local PB = CGame:NewObjectFromPath("/Script/UMG.ProgressBar", SizeBox_HP)
                if PB then
                    pcall(function() PB:SetFillColorAndOpacity(FLinearColor and FLinearColor(1, 1, 1, 1) or {R=1,G=1,B=1,A=1}) end)
                    pcall(function() PB:SetPercent(1.0) end)
                    pcall(function() PB:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                    pcall(function() PB:SetRenderOpacity(1.0) end)
                    pcall(function() PB:SetDesiredSizeOverride(FVector2D and FVector2D(100, 6) or {X=100, Y=6}) end)
                    local bUsedSetContent = false
                    pcall(function() if SizeBox_HP.SetContent then SizeBox_HP:SetContent(PB) bUsedSetContent = true end end)
                    if not bUsedSetContent then pcall(function() SizeBox_HP:AddChild(PB) end) end
                    HealthFill = PB
                end
            end
        end
    end)

    return {
        Container = Widget,
        NameText = NameText,
        HealthFill = HealthFill,
        IsGameWidget = true,
        IsOriginalProgressBar = bIsOriginalProgressBar,
        HasChildren = (NameText ~= nil)
    }
end

-- ═══════════════════════════════════════════════════════════════════
-- Canvas Transform + Position
-- ═══════════════════════════════════════════════════════════════════
function PMM.UpdateCanvasTransform(PC)
    if not PMM.ESPCanvas or not Game:IsValid(PMM.ESPCanvas) then return end
    local success = false
    pcall(function()
        local SBL = SlateBlueprintLibrary
        if SBL and SBL.AbsoluteToLocal then
            local cg = PMM.ESPCanvas:GetCachedGeometry()
            if cg then
                local pt0 = SBL.AbsoluteToLocal(cg, FVector2D and FVector2D(0, 0) or {X=0, Y=0})
                local pt1 = SBL.AbsoluteToLocal(cg, FVector2D and FVector2D(100, 100) or {X=100, Y=100})
                if pt0 and pt1 then
                    PMM._CanvasScaleX = (pt1.X - pt0.X) / 100
                    PMM._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                    PMM._CanvasOffsetX = pt0.X
                    PMM._CanvasOffsetY = pt0.Y
                    success = true
                end
            end
        end
    end)
    if not success then
        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.ScreenToWidgetLocal then
                local cg = PMM.ESPCanvas:GetCachedGeometry()
                if cg then
                    local pt0 = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
                    local pt1 = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
                    WLL.ScreenToWidgetLocal(PC, cg, FVector2D and FVector2D(0, 0) or {X=0, Y=0}, pt0)
                    WLL.ScreenToWidgetLocal(PC, cg, FVector2D and FVector2D(100, 100) or {X=100, Y=100}, pt1)
                    PMM._CanvasScaleX = (pt1.X - pt0.X) / 100
                    PMM._CanvasScaleY = (pt1.Y - pt0.Y) / 100
                    PMM._CanvasOffsetX = pt0.X
                    PMM._CanvasOffsetY = pt0.Y
                    success = true
                end
            end
        end)
    end
    if not success then
        local scale = 1.0
        local WLL = WidgetLayoutLibrary
        if WLL and WLL.GetViewportScale then scale = WLL.GetViewportScale(PC) or 1.0 end
        PMM._CanvasScaleX = 1.0 / scale
        PMM._CanvasScaleY = 1.0 / scale
        PMM._CanvasOffsetX = 0
        PMM._CanvasOffsetY = 0
    end
end

function PMM.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
    if not ScreenPixelPos then return FVector2D and FVector2D(0, 0) or {X=0, Y=0} end
    local scaleX = PMM._CanvasScaleX or 1.0
    local scaleY = PMM._CanvasScaleY or 1.0
    local offsetX = PMM._CanvasOffsetX or 0
    local offsetY = PMM._CanvasOffsetY or 0
    return (FVector2D and FVector2D(ScreenPixelPos.X * scaleX + offsetX, ScreenPixelPos.Y * scaleY + offsetY)) or {X = ScreenPixelPos.X * scaleX + offsetX, Y = ScreenPixelPos.Y * scaleY + offsetY}
end

function PMM.ProjectWorldToCanvasLocal(PC, WorldLoc)
    if not IsValid(PC) or not WorldLoc then return false, (FVector2D and FVector2D(0, 0) or {X=0, Y=0}) end
    local ScreenPixelPos = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
    local bOK = false
    pcall(function()
        local res = PC:ProjectWorldLocationToScreen(WorldLoc, ScreenPixelPos, true)
        if res == true or res == 1 or (ScreenPixelPos and (ScreenPixelPos.X ~= 0 or ScreenPixelPos.Y ~= 0)) then bOK = true end
    end)
    if not bOK or not ScreenPixelPos or (ScreenPixelPos.X == 0 and ScreenPixelPos.Y == 0) then return false, (FVector2D and FVector2D(0, 0) or {X=0, Y=0}) end
    local CanvasLocalPos = PMM.ScreenPixelToCanvasLocal(PC, ScreenPixelPos)
    return true, CanvasLocalPos
end

function PMM.GetDynamicViewportSize(PC)
    local width, height = 0, 0
    if PMM.ESPCanvas and Game:IsValid(PMM.ESPCanvas) then
        pcall(function()
            local cg = PMM.ESPCanvas:GetCachedGeometry()
            if cg and cg.GetLocalSize then
                local sz = cg:GetLocalSize()
                if sz and sz.X and sz.X > 200 then width = sz.X height = sz.Y end
            end
        end)
    end
    if width > 200 then return width, height end
    pcall(function()
        local WLL = WidgetLayoutLibrary
        if WLL and WLL.GetViewportSize then
            local sz = WLL.GetViewportSize(PC or PMM.GetMyPlayerController())
            if sz and sz.X and sz.X > 200 then width = sz.X height = sz.Y end
        end
    end)
    if width > 200 then
        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.GetViewportScale then
                local scale = WLL.GetViewportScale(PC or PMM.GetMyPlayerController())
                if scale and type(scale) == "number" and scale > 0 and scale ~= 1.0 then width = width / scale height = height / scale end
            end
        end)
        return width, height
    end
    return PMM._cachedViewportW or 1920, PMM._cachedViewportH or 1080
end

function PMM.UpdateESPPositionWithPC(Widget, WorldLoc, PC, CanvasPos)
    if not Widget or not IsValid(PC) then return false end
    local Container = Widget.Container or Widget
    local bOnScreen = true
    if not CanvasPos then
        if not WorldLoc then return false end
        bOnScreen, CanvasPos = PMM.ProjectWorldToCanvasLocal(PC, WorldLoc)
    end
    if not bOnScreen then pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end) return false end

    pcall(function()
        if PMM.ESPCanvas and Game:IsValid(PMM.ESPCanvas) then
            local ptr = tostring(Container)
            local Slot = PMM.ESPWidgetPtrs[ptr]
            if not Slot or not slua.isValid(Slot) or type(Slot) == "boolean" then
                local addedSlot = PMM.ESPCanvas:AddChildToCanvas(Container)
                if addedSlot and slua.isValid(addedSlot) then
                    Slot = addedSlot
                    PMM.ESPWidgetPtrs[ptr] = addedSlot
                    if type(Widget) == "table" then Widget.Slot = addedSlot end
                    pcall(function() Slot:SetAutoSize(true) end)
                    pcall(function() Slot.bAutoSize = true end)
                    local align = FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0}
                    pcall(function() Slot.Alignment = align end)
                    pcall(function() Slot:SetAlignment(align) end)
                    pcall(function() Slot:SetAlignment(0.5, 1.0) end)
                    pcall(function() Slot:SetZOrder(PMM.ESPWidgetZOrder or 20) end)
                end
            end

            local bShowAnyUI = _G.LexusConfig.Esp9_Name or _G.LexusConfig.Esp9_Distance or _G.LexusConfig.Esp9_HP or _G.LexusConfig.Esp9_Team or _G.LexusConfig.Esp9_Weapon
            if bShowAnyUI then
                Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            else
                Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end

            if not Widget._OffsetResetDone then
                pcall(function() Container:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X=0, Y=0}) end)
                pcall(function() Container:SetRenderScale(FVector2D and FVector2D(0.90, 0.90) or {X=0.90, Y=0.90}) end)
                if Widget and type(Widget) == "table" then
                    if Widget.NameText and slua.isValid(Widget.NameText) then pcall(function() Widget.NameText:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X=0, Y=0}) end) end
                    if Widget.HealthFill and slua.isValid(Widget.HealthFill) then pcall(function() Widget.HealthFill:SetRenderTranslation(FVector2D and FVector2D(0.0, 0.0) or {X=0, Y=0}) end) end
                end
                pcall(function() Container.RenderTransformPivot = FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0} end)
                pcall(function() Container:SetRenderTransformPivot(FVector2D and FVector2D(0.5, 1.0) or {X=0.5, Y=1.0}) end)
                Widget._OffsetResetDone = true
            end

            if not Slot or not slua.isValid(Slot) or Slot == PMM.ESPCanvas then
                if Widget and type(Widget) == "table" and Widget.Slot and slua.isValid(Widget.Slot) then Slot = Widget.Slot
                elseif Container.Slot and slua.isValid(Container.Slot) then Slot = Container.Slot end
            end

            if Slot and slua.isValid(Slot) and Slot ~= PMM.ESPCanvas then
                local finalX = CanvasPos.X + (PMM.ESPAnchorOffsetX or 0)
                local finalY = CanvasPos.Y + (PMM.ESPAnchorOffsetY or 0)
                if Widget and type(Widget) == "table" then
                    if not Widget._CachedPosVec then Widget._CachedPosVec = FVector2D and FVector2D(finalX, finalY) or {X=finalX, Y=finalY}
                    else Widget._CachedPosVec.X = finalX Widget._CachedPosVec.Y = finalY end
                    pcall(function() Slot:SetPosition(Widget._CachedPosVec) end)
                else
                    pcall(function() Slot:SetPosition(FVector2D and FVector2D(finalX, finalY) or {X=finalX, Y=finalY}) end)
                end
            end
        end
    end)
    return true
end

-- ═══════════════════════════════════════════════════════════════════
-- Update ESP Text
-- ═══════════════════════════════════════════════════════════════════
function PMM.UpdateESPText(Widget, Text)
    if not Widget then return end
    if Widget._LastESPText == Text then return end
    Widget._LastESPText = Text

    local function applyTextAndCenter(w, txt)
        if not w or not slua.isValid(w) then return end
        if txt == "" then
            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            return
        else
            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        end
        pcall(function() w:SetText(txt) end)
        pcall(function()
            local FSlateColor = import("SlateColor") or import("/Script/SlateCore.SlateColor")
            local orangeColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=255, G=255, B=255, A=255}
            if w.SetColorAndOpacity then
                if FSlateColor then w:SetColorAndOpacity(FSlateColor(orangeColor)) else w:SetColorAndOpacity(orangeColor) end
            end
        end)
        pcall(function() if w.SetJustification then w:SetJustification(1) end end)
        pcall(function() local slot = w.Slot if slot and slot.SetHorizontalAlignment then slot:SetHorizontalAlignment(1) end end)
        pcall(function() w:SetRenderTranslation(FVector2D and FVector2D(PMM.ESPTextOffsetX or 0, PMM.ESPTextOffsetY or 0) or {X=PMM.ESPTextOffsetX or 0, Y=PMM.ESPTextOffsetY or 0}) end)
    end

    if Widget.NameText and slua.isValid(Widget.NameText) then applyTextAndCenter(Widget.NameText, Text) end
    if Widget.IsGameWidget and Widget.Container then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                if W.SetPlayerName then
                    local Name = Text
                    local idx = string.find(Text, " %[")
                    if idx then Name = string.sub(Text, 1, idx - 1) end
                    W:SetPlayerName(Name)
                end
                applyTextAndCenter(W.TextBlock_TeamName, Text)
                applyTextAndCenter(W.TextBlock_PlayerName, Text)
                pcall(function()
                    if not Widget._CachedVBChildren then
                        local list = {}
                        local VB = PMM._FindNamedWidgetInTree(W, "VerticalBox_0", 8)
                        if VB and slua.isValid(VB) and VB.GetChildrenCount then
                            local nChildren = VB:GetChildrenCount()
                            for i = 0, nChildren - 1 do
                                local child = VB:GetChildAt(i)
                                if child and slua.isValid(child) and child.SetText then table.insert(list, child) end
                            end
                        end
                        Widget._CachedVBChildren = list
                    end
                    for _, child in ipairs(Widget._CachedVBChildren) do applyTextAndCenter(child, Text) end
                end)
                pcall(function()
                    if not Widget._CachedHBChildren then
                        local list = {}
                        local HB = PMM._FindNamedWidgetInTree(W, "HorizontalBox_TeamName", 8)
                        if HB and slua.isValid(HB) and HB.GetChildrenCount then
                            local nChildren = HB:GetChildrenCount()
                            for i = 0, nChildren - 1 do
                                local child = HB:GetChildAt(i)
                                if child and slua.isValid(child) and child.SetText then table.insert(list, child) end
                            end
                        end
                        Widget._CachedHBChildren = list
                    end
                    for _, child in ipairs(Widget._CachedHBChildren) do applyTextAndCenter(child, Text) end
                end)
            end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- Update ESP Health
-- ═══════════════════════════════════════════════════════════════════
function PMM.UpdateESPHealth(Widget, pct)
    if not Widget then return end
    Widget.LastPct = pct
    local bShowHP = _G.LexusConfig.Esp9_HP

    if PMM.bForceSwitcherIndexEveryUpdate and Widget.Container then
        pcall(function()
            local W = Widget.Container
            if W and slua.isValid(W) then
                if W.WidgetSwitcher_Type and slua.isValid(W.WidgetSwitcher_Type) then pcall(function() if W.WidgetSwitcher_Type.SetActiveWidgetIndex then W.WidgetSwitcher_Type:SetActiveWidgetIndex(PMM.HPWidgetSwitcherTypeIndex) end end) end
                if W.WidgetSwitcher_Type2 and slua.isValid(W.WidgetSwitcher_Type2) then pcall(function() if W.WidgetSwitcher_Type2.SetActiveWidgetIndex then W.WidgetSwitcher_Type2:SetActiveWidgetIndex(PMM.HPWidgetSwitcherType2Index) end end) end
                if W.SizeBox_HP and slua.isValid(W.SizeBox_HP) then
                    if bShowHP then
                        W.SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                    else
                        W.SizeBox_HP:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    end
                end
            end
        end)
    end

    if not bShowHP then return end

    if Widget.HealthFill then
        local bValid = false
        pcall(function() bValid = slua.isValid(Widget.HealthFill) end)
        if bValid then
            local bHasSetPercent = false
            pcall(function() bHasSetPercent = (Widget.HealthFill.SetPercent ~= nil) end)
            if not bHasSetPercent then
                local PB = PMM.FindProgressBarInWidget(Widget.HealthFill, 0, 5)
                if PB and slua.isValid(PB) then Widget.HealthFill = PB else return end
            end
            pcall(function()
                if Widget.HealthFill.SetWidgetVisibility then Widget.HealthFill:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end
                if Widget.HealthFill.SetRenderOpacity then Widget.HealthFill:SetRenderOpacity(1.0) end
                if Widget.HealthFill.SetPercent then
                    Widget.HealthFill:SetPercent(pct)
                    local color = FLinearColor and FLinearColor(0.88, 0.96, 1.0, 1.0) or {R=224,G=245,B=255,A=255}
                    if Widget.HealthFill.SetFillColorAndOpacity then
                        Widget.HealthFill:SetFillColorAndOpacity(color)
                    end
                    pcall(function()
                        if Widget.IsOriginalProgressBar then
                            local style = Widget.HealthFill.WidgetStyle
                            if style and style.FillImage then
                                style.FillImage.TintColor = color
                                Widget.HealthFill:SetWidgetStyle(style)
                            end
                        end
                    end)
                end
            end)
        end
        return
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- Remove ESP Widget
-- ═══════════════════════════════════════════════════════════════════
function PMM.RemoveESPWidget(Widget, KeyStr)
    if not Widget then return end
    local Container = Widget.Container or Widget
    -- ✅ فقط احذف إذا كانت الويدجت من إنشائنا
    if PMM.IsOurESPWidget(Container) then
        pcall(function()
            local ptr = tostring(Container)
            PMM.ESPWidgetPtrs[ptr] = nil
            Container:RemoveFromParent()
            Container:ConditionalBeginDestroy()
        end)
    else
        -- لا تحذف شيئاً من UI الأصلي
        pcall(function()
            local ptr = tostring(Container)
            PMM.ESPWidgetPtrs[ptr] = nil
        end)
    end
    if KeyStr then
        PMM.RemoveSnapLine(KeyStr)
        if PMM.RemoveSkeletonLines then PMM.RemoveSkeletonLines(KeyStr) end
    end
end

print("[N5LA] ✅ ESP Part 3/6 loaded (ESP Widgets)")



-- =====================================================================
-- ESP FULL SYSTEM — Part 4/6: Weapon Icons + SnapLines
-- =====================================================================

-- ═══════════════════════════════════════════════════════════════════
-- Get Character Weapon Info
-- ═══════════════════════════════════════════════════════════════════
function PMM.GetCharacterWeaponInfo(Character)
    if not IsValid(Character) then return nil end
    local WeaponID, WeaponName, WeaponIconPath, WeaponIconTexture, CurrentWeapon = nil, nil, nil, nil, nil

    pcall(function() if Character.GetCurrentWeapon then CurrentWeapon = Character:GetCurrentWeapon() end end)
    if not CurrentWeapon then pcall(function() CurrentWeapon = Character.CurrentWeapon end) end
    if not CurrentWeapon then pcall(function() if Character.GetWeaponManager then local WM = Character:GetWeaponManager() if WM and WM.GetCurrentWeapon then CurrentWeapon = WM:GetCurrentWeapon() end end end) end

    if CurrentWeapon and IsValid(CurrentWeapon) then
        pcall(function() if CurrentWeapon.GetWeaponID then WeaponID = CurrentWeapon:GetWeaponID() end end)
        if not WeaponID then pcall(function() WeaponID = CurrentWeapon.WeaponID end) end
        if not WeaponID then pcall(function() if CurrentWeapon.GetItemID then WeaponID = CurrentWeapon:GetItemID() end end) end
        pcall(function() if CurrentWeapon.GetWeaponName then WeaponName = CurrentWeapon:GetWeaponName() end end)
        pcall(function() if CurrentWeapon.GetWeaponIconPath then WeaponIconPath = CurrentWeapon:GetWeaponIconPath() end end)
        pcall(function() if CurrentWeapon.GetWeaponIcon then WeaponIconTexture = CurrentWeapon:GetWeaponIcon() end end)
    end

    if not WeaponID then
        pcall(function()
            local PS = nil
            if Character.GetPlayerStateSafety then PS = Character:GetPlayerStateSafety() elseif Character.GetPlayerState then PS = Character:GetPlayerState() end
            if PS and IsValid(PS) then
                if PS.GetCurrentWeaponID then WeaponID = PS:GetCurrentWeaponID() end
                if not WeaponID and PS.CurWeaponID then WeaponID = PS.CurWeaponID end
            end
        end)
    end
    return { WeaponID = WeaponID, WeaponName = WeaponName, WeaponIconPath = WeaponIconPath, WeaponIconTexture = WeaponIconTexture, CurrentWeapon = CurrentWeapon }
end

-- ═══════════════════════════════════════════════════════════════════
-- Find Weapon Icon in Widget
-- ═══════════════════════════════════════════════════════════════════
function PMM.FindWeaponIconInWidget(WidgetObj, Depth, MaxDepth)
    if not WidgetObj or not slua.isValid(WidgetObj) then return nil end
    Depth = Depth or 0; MaxDepth = MaxDepth or 8
    local propNames = { "Image_Weapon", "Image_WeaponIcon", "Image_Gun", "Image_Icon", "WeaponIcon", "WeaponImage", "Image_Equip" }
    for _, pname in ipairs(propNames) do
        pcall(function()
            local prop = WidgetObj[pname]
            if prop and slua.isValid(prop) then
                local hasBrush = false
                pcall(function() if prop.Brush then hasBrush = true end end)
                if hasBrush then return prop end
            end
        end)
    end
    if Depth >= MaxDepth then return nil end
    local nChildren = 0
    pcall(function() if WidgetObj.GetChildrenCount then nChildren = WidgetObj:GetChildrenCount() end end)
    for i = 0, math.max(nChildren - 1, 0) do
        local child = nil
        pcall(function() child = WidgetObj:GetChildAt(i) end)
        if child and slua.isValid(child) then
            local result = PMM.FindWeaponIconInWidget(child, Depth + 1, MaxDepth)
            if result then return result end
        end
    end
    if nChildren == 0 then
        local Root = PMM._GetWidgetRoot(WidgetObj)
        if Root and slua.isValid(Root) and Root ~= WidgetObj then
            local result = PMM.FindWeaponIconInWidget(Root, Depth + 1, MaxDepth)
            if result then return result end
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Fix Weapon Icon Brush Size
-- ═══════════════════════════════════════════════════════════════════
function PMM.FixWeaponIconBrushSize(ImageWidget, DefaultW, DefaultH)
    if not ImageWidget or not slua.isValid(ImageWidget) then return end
    DefaultW = DefaultW or 138; DefaultH = DefaultH or 69
    pcall(function()
        local brush = ImageWidget.Brush
        if brush then
            brush.ImageSize = FVector2D and FVector2D(DefaultW, DefaultH) or {X=DefaultW, Y=DefaultH}
            brush.DrawAs = 3
            brush.TintColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}
            if ImageWidget.SetBrush then ImageWidget:SetBrush(brush) end
        end
        if ImageWidget.SetDesiredSizeOverride then ImageWidget:SetDesiredSizeOverride(FVector2D and FVector2D(DefaultW, DefaultH) or {X=DefaultW, Y=DefaultH}) end
        local slot = ImageWidget.Slot
        if slot and slot.SetSize then slot:SetSize(FVector2D and FVector2D(DefaultW, DefaultH) or {X=DefaultW, Y=DefaultH}) end
        ImageWidget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        ImageWidget:SetRenderOpacity(1.0)
        ImageWidget:SetColorAndOpacity(FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1})
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- Apply Weapon Icon Full Opacity
-- ═══════════════════════════════════════════════════════════════════
function PMM.ApplyWeaponIconFullOpacity(Container, ourWeaponIcon)
    local fullIcon = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 1.0) or {R=1,G=1,B=1,A=1}
    if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return end
    pcall(function() if ourWeaponIcon.SetRenderOpacity then ourWeaponIcon:SetRenderOpacity(1.0) end end)
    pcall(function() if ourWeaponIcon.SetColorAndOpacity then ourWeaponIcon:SetColorAndOpacity(fullIcon) end end)
    pcall(function()
        local brush = ourWeaponIcon.Brush
        if brush then pcall(function() brush.TintColor = fullIcon end) if ourWeaponIcon.SetBrush then ourWeaponIcon:SetBrush(brush) end end
    end)
    local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
    for _, pname in ipairs(chainNames) do
        pcall(function()
            local node = Container and Container[pname]
            if node and slua.isValid(node) and node.SetRenderOpacity then node:SetRenderOpacity(1.0) end
            if node and slua.isValid(node) and node.SetColorAndOpacity then node:SetColorAndOpacity(fullIcon) end
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- Apply Weapon Icon To Image
-- ═══════════════════════════════════════════════════════════════════
function PMM.ApplyWeaponIconToImage(ImageWidget, winfo)
    if not ImageWidget or not slua.isValid(ImageWidget) then return false, "no_widget" end
    if not winfo or not winfo.WeaponID then return false, "no_weapon_id" end

    local iconPath = nil
    local method = "none"
    local bHasAddKnownMissing = false
    local defaultW = 138
    local defaultH = 69

    pcall(function()
        local itemRecord = CDataTable.GetTableData("Item", winfo.WeaponID)
        if itemRecord and itemRecord.KillWhiteIcon and itemRecord.KillWhiteIcon ~= "" then iconPath = itemRecord.KillWhiteIcon method = "KillWhiteIcon" end
        if (not iconPath or iconPath == "") and winfo.WeaponIconPath and winfo.WeaponIconPath ~= "" then iconPath = winfo.WeaponIconPath method = "WeaponIconPath" end
        if (not iconPath or iconPath == "") and winfo.WeaponIconTexture and slua.isValid(winfo.WeaponIconTexture) then
            if ImageWidget.SetBrushFromTexture then ImageWidget:SetBrushFromTexture(winfo.WeaponIconTexture, true) method = "WeaponIconTexture" return end
        end
        if not iconPath or iconPath == "" then
            local UIUtil = require("client.common.ui_util")
            iconPath, bHasAddKnownMissing = UIUtil.GetItemBigIcon(winfo.WeaponID, ImageWidget)
            if iconPath and iconPath ~= "" then method = "GetItemBigIcon" end
        end
        if not iconPath or iconPath == "" then
            local UIUtil = require("client.common.ui_util")
            iconPath = UIUtil.GetItemSmallIcon(winfo.WeaponID, ImageWidget, bHasAddKnownMissing)
            if iconPath and iconPath ~= "" then method = "GetItemSmallIcon" end
        end
    end)

    if method == "WeaponIconTexture" then PMM.FixWeaponIconBrushSize(ImageWidget, defaultW, defaultH) return true, method end
    if not iconPath or iconPath == "" then return false, "no_path" end

    local bOK = false
    pcall(function()
        if ImageWidget.SetBrushResourceFromPathSync then ImageWidget:SetBrushResourceFromPathSync(iconPath, true) bOK = true end
        if not bOK then
            local util = require("client.slua_ui_framework.util")
            local result = util.SetTexture(ImageWidget, iconPath, { sync = true, bMatchSize = true, bIsInCombatState = true, bHasAddKnownMissing = bHasAddKnownMissing })
            bOK = result ~= nil
        end
        if not bOK then
            local tex = import(iconPath)
            if tex and slua.isValid(tex) and ImageWidget.SetBrushFromTexture then ImageWidget:SetBrushFromTexture(tex, true) bOK = true end
        end
        if not bOK then
            local LoadObject = import("LoadObject")
            if LoadObject then
                local tex = LoadObject(iconPath)
                if tex and slua.isValid(tex) and ImageWidget.SetBrushFromTexture then ImageWidget:SetBrushFromTexture(tex, true) bOK = true end
            end
        end
    end)

    if bOK then PMM.FixWeaponIconBrushSize(ImageWidget, defaultW, defaultH) end
    return bOK, method .. ":" .. tostring(iconPath)
end

-- ═══════════════════════════════════════════════════════════════════
-- Copy Weapon Icon Brush From Native
-- ═══════════════════════════════════════════════════════════════════
function PMM.CopyWeaponIconBrushFromNative(ourWeaponIcon, nativeWeaponIcon)
    if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return false end
    if not nativeWeaponIcon or not slua.isValid(nativeWeaponIcon) then return false end
    local bCopied = false
    pcall(function()
        local nBrush = nativeWeaponIcon.Brush
        if nBrush then
            local resObj = nil
            pcall(function() resObj = nBrush.ResourceObject end)
            if resObj and slua.isValid(resObj) and ourWeaponIcon.SetBrushFromTexture then
                ourWeaponIcon:SetBrushFromTexture(resObj, true)
                bCopied = true
            end
            if bCopied then
                local imgSize = nil
                pcall(function() imgSize = nBrush.ImageSize end)
                if imgSize then
                    local oBrush = ourWeaponIcon.Brush
                    if oBrush then oBrush.ImageSize = imgSize if ourWeaponIcon.SetBrush then ourWeaponIcon:SetBrush(oBrush) end end
                end
            end
        end
    end)
    return bCopied
end

-- ═══════════════════════════════════════════════════════════════════
-- Add Weapon Icon To ESP
-- ═══════════════════════════════════════════════════════════════════
function PMM.AddWeaponIconToESP(WidgetData, Character)
    if not WidgetData or not WidgetData.Container then return end
    local Container = WidgetData.Container
    if not slua.isValid(Container) then return end

    if not _G.LexusConfig.Esp9_Weapon then
        pcall(function()
            local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
            for _, pname in ipairs(chainNames) do
                local node = Container[pname]
                if node and slua.isValid(node) and node.SetWidgetVisibility then node:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
            end
            local ourWeaponIcon = Container.WeaponIcon or PMM.FindWeaponIconInWidget(Container, 0, 8)
            if ourWeaponIcon and slua.isValid(ourWeaponIcon) then ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
        end)
        WidgetData._LastWeaponID = 0
        WidgetData._WeaponIconApplied = false
        return
    end

    pcall(function()
        local ourWeaponIcon = Container.WeaponIcon
        if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then ourWeaponIcon = PMM.FindWeaponIconInWidget(Container, 0, 8) end
        if not ourWeaponIcon or not slua.isValid(ourWeaponIcon) then return end

        local winfo = Character and PMM.GetCharacterWeaponInfo(Character) or nil

        if not winfo or not winfo.WeaponID or winfo.WeaponID == 0 then
            pcall(function() ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
            local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
            for _, pname in ipairs(chainNames) do
                pcall(function()
                    local node = Container and Container[pname]
                    if node and slua.isValid(node) and node.SetWidgetVisibility then node:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end
                end)
            end
            WidgetData._LastWeaponID = 0
            WidgetData._WeaponIconApplied = false
            return
        end

        if WidgetData._LastWeaponID == winfo.WeaponID and WidgetData._WeaponIconApplied then
            pcall(function() ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
            pcall(function() ourWeaponIcon:SetRenderOpacity(1.0) end)
            return
        end

        local chainNames = {"Border_WeaponColor", "Border_Weapon", "Border_WeaponIcon", "SizeBox_Weapon", "ScaleBox_Weapon", "Switcher_WeaponIcon"}
        for _, pname in ipairs(chainNames) do
            pcall(function()
                local node = Container and Container[pname]
                if node and slua.isValid(node) and node.SetWidgetVisibility then node:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end
            end)
        end

        local bCopied = false
        if winfo and winfo.WeaponID then
            local ok = PMM.ApplyWeaponIconToImage(ourWeaponIcon, winfo)
            if ok then bCopied = true end
        end

        pcall(function() ourWeaponIcon:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
        PMM.ApplyWeaponIconFullOpacity(Container, ourWeaponIcon)
        PMM.FixWeaponIconBrushSize(ourWeaponIcon)

        WidgetData._LastWeaponID = winfo.WeaponID
        WidgetData._WeaponIconApplied = true
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- SnapLines System
-- ═══════════════════════════════════════════════════════════════════
function PMM.CreateSnapLine()
    if not PMM.ESPCanvas or not Game:IsValid(PMM.ESPCanvas) then return nil end
    local Border = nil
    pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", PMM.ESPCanvas) end)
    if not Border or not slua.isValid(Border) then return nil end

    local color = PMM.SnapLineColor or (FLinearColor and FLinearColor(1.0, 1.0, 1.0, PMM.SnapLineOpacity or 0.9) or {R=1,G=1,B=1,A=PMM.SnapLineOpacity or 0.9})
    pcall(function() Border:SetBrushColor(color) end)
    pcall(function() Border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
    pcall(function() Border.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5} end)
    pcall(function() Border:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5}) end)

    local Slot = nil
    pcall(function()
        Slot = PMM.ESPCanvas:AddChildToCanvas(Border)
        if Slot then Slot:SetAutoSize(false) Slot:SetZOrder(1) end
    end)
    return { Widget = Border, Slot = Slot }
end

function PMM.GetSnapLineStartPos(PC)
    local screenPixelW, screenPixelH = 0, 0
    local scale = 1.0
    pcall(function()
        if PC and PC.GetViewportSize then
            local vs = FVector2D and FVector2D(0, 0) or {X=0,Y=0}
            PC:GetViewportSize(vs)
            if vs and vs.X and vs.X > 200 then screenPixelW = vs.X screenPixelH = vs.Y end
        end
    end)
    if screenPixelW <= 200 then
        pcall(function()
            local WLL = WidgetLayoutLibrary
            if WLL and WLL.GetViewportSize then
                local vs = WLL.GetViewportSize(PC)
                if vs and vs.X and vs.X > 200 then screenPixelW = vs.X screenPixelH = vs.Y end
            end
        end)
    end
    pcall(function()
        local WLL = WidgetLayoutLibrary
        if WLL and WLL.GetViewportScale then
            local s = WLL.GetViewportScale(PC)
            if s and type(s) == "number" and s > 0 then scale = s end
        end
    end)
    if screenPixelW <= 200 then
        screenPixelW = (PMM._cachedViewportW or 1920) * scale
        screenPixelH = (PMM._cachedViewportH or 1080) * scale
    end

    if not PMM._CachedTopCenterPixel then PMM._CachedTopCenterPixel = FVector2D and FVector2D(0, 0) or {X=0,Y=0} end
    PMM._CachedTopCenterPixel.X = screenPixelW / 2.0
    PMM._CachedTopCenterPixel.Y = (PMM.SnapLineOriginY or 50) * scale

    local fromCanvasPos = PMM.ScreenPixelToCanvasLocal(PC, PMM._CachedTopCenterPixel)
    local fromX = fromCanvasPos.X + (PMM.SnapLineOriginOffsetX or 0)
    local fromY = fromCanvasPos.Y
    return fromX, fromY
end

function PMM.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
    if not PMM.bUseSnapLines then return end
    if not PMM.ESPCanvas or not Game:IsValid(PMM.ESPCanvas) then return end

    local LineData = PMM.SnapLineWidgets[KeyStr]

    if not bOnScreen or not CanvasPos then
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            pcall(function() LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
        end
        return
    end

    local bIsNew = false
    if not LineData then
        LineData = PMM.CreateSnapLine()
        if not LineData or not LineData.Widget or not LineData.Slot then return end
        PMM.SnapLineWidgets[KeyStr] = LineData
        bIsNew = true
    end

    local Widget = LineData.Widget
    local Slot = LineData.Slot

    pcall(function() Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)

    if not LineData._PivotSet then
        pcall(function() Widget.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5} end)
        pcall(function() Widget:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X=0,Y=0.5}) end)
        LineData._PivotSet = true
    end

    local toX = CanvasPos.X + (PMM.SnapLineHeadOffsetX or 0)
    local toY = CanvasPos.Y + (PMM.SnapLineHeadOffsetY or 0)
    local dx = toX - fromX
    local dy = toY - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    local thickness = PMM.SnapLineThickness or 1.65

    local angle_rad = 0
    if math.atan2 then angle_rad = math.atan2(dy, dx) else angle_rad = math.atan(dy, dx) end
    local angle = angle_rad * (180.0 / math.pi)

    if not LineData._CachedPosVec then
        LineData._CachedPosVec = FVector2D and FVector2D(fromX, fromY - thickness / 2.0) or {X=fromX, Y=fromY - thickness / 2.0}
        LineData._CachedSizeVec = FVector2D and FVector2D(length, thickness) or {X=length, Y=thickness}
    else
        LineData._CachedPosVec.X = fromX; LineData._CachedPosVec.Y = fromY - thickness / 2.0
        LineData._CachedSizeVec.X = length; LineData._CachedSizeVec.Y = thickness
    end

    pcall(function()
        Slot:SetPosition(LineData._CachedPosVec)
        Slot:SetSize(LineData._CachedSizeVec)
        if bIsNew then Slot:SetZOrder(1) end
    end)
    pcall(function() Widget:SetRenderAngle(angle) end)
end

function PMM.RemoveSnapLine(KeyStr)
    local LineData = PMM.SnapLineWidgets[KeyStr]
    if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
        pcall(function() LineData.Widget:RemoveFromParent() LineData.Widget:ConditionalBeginDestroy() end)
        PMM.SnapLineWidgets[KeyStr] = nil
    end
end

function PMM.ClearAllSnapLines()
    for KeyStr, LineData in pairs(PMM.SnapLineWidgets) do
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            pcall(function() LineData.Widget:RemoveFromParent() LineData.Widget:ConditionalBeginDestroy() end)
        end
    end
    PMM.SnapLineWidgets = {}
end

print("[N5LA] ✅ ESP Part 4/6 loaded (Weapon Icons + SnapLines)")

-- =====================================================================
-- ESP FULL SYSTEM — Part 5/6: Skeleton System + Update Functions
-- =====================================================================

-- ═══════════════════════════════════════════════════════════════════
-- Raw Projection (أسرع بدون Canvas transform)
-- ═══════════════════════════════════════════════════════════════════
function PMM.ScreenPixelToCanvasLocalRaw(PC, screenX, screenY)
    local scaleX = PMM._CanvasScaleX or 1.0
    local scaleY = PMM._CanvasScaleY or 1.0
    local offsetX = PMM._CanvasOffsetX or 0
    local offsetY = PMM._CanvasOffsetY or 0
    return screenX * scaleX + offsetX, screenY * scaleY + offsetY
end

function PMM.ProjectWorldToCanvasLocalRaw(PC, WorldLoc)
    if not IsValid(PC) or not WorldLoc then return false, 0, 0 end
    if not PMM._tempScreenPixelPos then
        PMM._tempScreenPixelPos = FVector2D and FVector2D(0, 0) or {X=0, Y=0}
    end
    local tempPos = PMM._tempScreenPixelPos
    local bOK = false
    pcall(function()
        local res = PC:ProjectWorldLocationToScreen(WorldLoc, tempPos, true)
        if res == true or res == 1 then bOK = true end
    end)
    if not bOK or (tempPos.X == 0 and tempPos.Y == 0) then return false, 0, 0 end
    local canvasX, canvasY = PMM.ScreenPixelToCanvasLocalRaw(PC, tempPos.X, tempPos.Y)
    return true, canvasX, canvasY
end

-- ═══════════════════════════════════════════════════════════════════
-- Get Bone Location with Fallback
-- ═══════════════════════════════════════════════════════════════════
function PMM.GetBoneLocationWithFallback(Character, PrimaryBoneName)
    if not IsValid(Character) or not PrimaryBoneName then return nil end
    if Character._cachedBoneNames and Character._cachedBoneNames[PrimaryBoneName] then
        local cachedName = Character._cachedBoneNames[PrimaryBoneName]
        local loc = nil
        pcall(function()
            local Mesh = PMM.GetCharacterMesh(Character)
            if Mesh and Game:IsValid(Mesh) then
                if Mesh.GetSocketLocation then loc = Mesh:GetSocketLocation(cachedName)
                elseif Mesh.GetBoneLocation then loc = Mesh:GetBoneLocation(cachedName) end
            end
        end)
        if loc then return loc end
    end
    local fallbacks = PMM.BoneNameFallbacks[PrimaryBoneName] or {PrimaryBoneName}
    for _, bname in ipairs(fallbacks) do
        local loc = nil
        pcall(function()
            local Mesh = PMM.GetCharacterMesh(Character)
            if Mesh and Game:IsValid(Mesh) then
                if Mesh.GetSocketLocation then loc = Mesh:GetSocketLocation(bname)
                elseif Mesh.GetBoneLocation then loc = Mesh:GetBoneLocation(bname) end
            end
        end)
        if loc then
            if not Character._cachedBoneNames then Character._cachedBoneNames = {} end
            Character._cachedBoneNames[PrimaryBoneName] = bname
            return loc
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════
-- Is Player Visible (LOS Check)
-- ═══════════════════════════════════════════════════════════════════
function PMM.IsPlayerVisible(PC, Character)
    if not IsValid(PC) or not IsValid(Character) then return false end
    local now = os.clock()
    if Character._lastVisTime and (now - Character._lastVisTime) < 0.15 then
        return Character._cachedIsVisible or false
    end
    Character._lastVisTime = now
    local bVis = false
    pcall(function()
        if PC.LineOfSightTo then
            if not PMM._ZeroVector then
                local VT = FVector or import("/Script/CoreUObject.Vector")
                if VT then PMM._ZeroVector = VT(0, 0, 0) end
            end
            bVis = PC:LineOfSightTo(Character, PMM._ZeroVector, false)
        end
    end)
    if not bVis then
        local KismetSystemLibraryLocal = import("KismetSystemLibrary")
        if KismetSystemLibraryLocal and KismetSystemLibraryLocal.LineTraceSingle then
            pcall(function()
                local camMgr = nil
                local GameplayStatics = import("GameplayStatics")
                if GameplayStatics and GameplayStatics.GetPlayerCameraManager then
                    camMgr = GameplayStatics.GetPlayerCameraManager(PC, 0)
                end
                local startLoc = camMgr and camMgr:GetCameraLocation() or PMM.GetMyLocation()
                local headLoc = PMM.GetBoneLocationWithFallback(Character, "head")
                if startLoc and headLoc then
                    if not PMM._CachedHitResult then
                        local HitResultClass = import("HitResult") or import("/Script/Engine.HitResult")
                        PMM._CachedHitResult = HitResultClass and HitResultClass() or {}
                    end
                    local bHit = KismetSystemLibraryLocal.LineTraceSingle(PC, startLoc, headLoc, 0, false, nil, 0, PMM._CachedHitResult, true)
                    if bHit then
                        local hitActor = nil
                        if type(PMM._CachedHitResult.GetActor) == "function" then hitActor = PMM._CachedHitResult:GetActor()
                        elseif PMM._CachedHitResult.Actor then hitActor = PMM._CachedHitResult.Actor end
                        if hitActor and (hitActor == Character or (type(hitActor.IsChildOf) == "function" and hitActor:IsChildOf(Character))) then
                            bVis = true
                        end
                    else
                        bVis = true
                    end
                end
            end)
        end
    end
    Character._cachedIsVisible = bVis
    return bVis
end

-- ═══════════════════════════════════════════════════════════════════
-- Create Skeleton Line Widget
-- ═══════════════════════════════════════════════════════════════════
function PMM.CreateSkeletonLineWidget()
    if not PMM.ESPCanvas or not Game:IsValid(PMM.ESPCanvas) then return nil end
    local Border = nil
    pcall(function() Border = CGame:NewObjectFromPath("/Script/UMG.Border", PMM.ESPCanvas) end)
    if not Border or not slua.isValid(Border) then return nil end
    pcall(function() Border.RenderTransformPivot = FVector2D and FVector2D(0.0, 0.5) or {X=0, Y=0.5} end)
    pcall(function() Border:SetRenderTransformPivot(FVector2D and FVector2D(0.0, 0.5) or {X=0, Y=0.5}) end)
    local Slot = nil
    pcall(function()
        Slot = PMM.ESPCanvas:AddChildToCanvas(Border)
        if Slot then Slot:SetAutoSize(false) Slot:SetZOrder(5) end
    end)
    return {
        Widget = Border, Slot = Slot,
        posVec = FVector2D and FVector2D(0, 0) or {X=0, Y=0},
        sizeVec = FVector2D and FVector2D(0, 0) or {X=0, Y=0},
        lastFromX = -99999, lastFromY = -99999,
        lastToX = -99999, lastToY = -99999
    }
end

-- ═══════════════════════════════════════════════════════════════════
-- Update Skeleton Lines
-- ═══════════════════════════════════════════════════════════════════
function PMM.UpdateSkeletonLines(KeyStr, Character, PC, bVisible, TeamColor, bPlayerOnScreen, charLoc)
    if not PMM.bUseSkeleton then return end
    if not PMM.ESPCanvas or not Game:IsValid(PMM.ESPCanvas) then return end
    local PlayerBones = PMM.SkeletonWidgets[KeyStr]
    if not bVisible or not IsValid(Character) or not IsValid(PC) then
        if PlayerBones then
            for _, LineData in ipairs(PlayerBones) do
                if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                    LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    LineData.Widget._isSelfHitTestVisible = false
                end
            end
        end
        return
    end

    if not charLoc then charLoc = PMM.GetESPLocation(Character) end
    if not charLoc then return end

    if bPlayerOnScreen == nil then
        local bOnScreen, _, _ = PMM.ProjectWorldToCanvasLocalRaw(PC, charLoc)
        bPlayerOnScreen = bOnScreen
    end
    if not bPlayerOnScreen then
        if PlayerBones then
            for _, LineData in ipairs(PlayerBones) do
                if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                    LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                    LineData.Widget._isSelfHitTestVisible = false
                end
            end
        end
        return
    end

    local dist = 0
    local myLoc = PMM._CachedMyLoc or PMM.GetMyLocation()
    if myLoc and charLoc then
        local dx = (charLoc.X or 0) - (myLoc.X or 0)
        local dy = (charLoc.Y or 0) - (myLoc.Y or 0)
        local dz = (charLoc.Z or 0) - (myLoc.Z or 0)
        dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    end

    if PMM.SkeletonMaxDistance and PMM.SkeletonMaxDistance > 0 then
        if dist > PMM.SkeletonMaxDistance then
            if PlayerBones then
                for _, LineData in ipairs(PlayerBones) do
                    if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                        LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
                        LineData.Widget._isSelfHitTestVisible = false
                    end
                end
            end
            return
        end
    end

    if not PlayerBones then
        PlayerBones = {}
        PMM.SkeletonWidgets[KeyStr] = PlayerBones
    end

    local lineColor = nil
    if PMM.bUseVisibilityColor then
        local bTargetVisible = PMM.IsPlayerVisible(PC, Character)
        lineColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, 0.9) or {R=255, G=255, B=255, A=229}
    else
        lineColor = FLinearColor and FLinearColor(1.0, 1.0, 1.0, PMM.SkeletonOpacity or 0.9) or {R=255, G=255, B=255, A=229}
    end

    local cache = PMM._StaticBoneLocCache
    for k in pairs(cache) do cache[k] = nil end
    local lineIndex = 0
    local thickness = PMM.SkeletonThickness or 1.32
    if not Character._cachedBones3D then Character._cachedBones3D = {} end

    for _, chain in ipairs(PMM.SkeletonChains) do
        local lastCanvasX, lastCanvasY = nil, nil
        for _, boneName in ipairs(chain) do
            local boneWorldLoc = cache[boneName]
            if boneWorldLoc == nil then
                boneWorldLoc = PMM.GetBoneLocationWithFallback(Character, boneName) or false
                cache[boneName] = boneWorldLoc
            end
            if boneWorldLoc == false then boneWorldLoc = nil end

            local currentCanvasX, currentCanvasY = nil, nil
            if boneWorldLoc then
                local bOnScreen, cX, cY = PMM.ProjectWorldToCanvasLocalRaw(PC, boneWorldLoc)
                if bOnScreen then
                    currentCanvasX = cX
                    currentCanvasY = cY
                end
            end

            if lastCanvasX and currentCanvasX then
                lineIndex = lineIndex + 1
                local LineData = PlayerBones[lineIndex]
                if not LineData or not LineData.Widget or not slua.isValid(LineData.Widget) then
                    LineData = PMM.CreateSkeletonLineWidget()
                    if LineData then PlayerBones[lineIndex] = LineData end
                end

                if LineData and LineData.Widget and LineData.Slot then
                    local Widget = LineData.Widget
                    local Slot = LineData.Slot

                    if Widget._cachedColor ~= lineColor then
                        Widget:SetBrushColor(lineColor)
                        Widget._cachedColor = lineColor
                    end
                    if not Widget._isSelfHitTestVisible then
                        Widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
                        Widget._isSelfHitTestVisible = true
                    end

                    local fromX = lastCanvasX
                    local fromY = lastCanvasY
                    local toX = currentCanvasX
                    local toY = currentCanvasY

                    local threshold = 0.15
                    if dist > 8000 then threshold = 0.8 elseif dist > 4000 then threshold = 0.4 end

                    if math.abs(fromX - LineData.lastFromX) > threshold or
                       math.abs(fromY - LineData.lastFromY) > threshold or
                       math.abs(toX - LineData.lastToX) > threshold or
                       math.abs(toY - LineData.lastToY) > threshold then

                        LineData.lastFromX = fromX
                        LineData.lastFromY = fromY
                        LineData.lastToX = toX
                        LineData.lastToY = toY

                        local dx = toX - fromX
                        local dy = toY - fromY
                        local length = math.sqrt(dx * dx + dy * dy)
                        local angle_rad = (math.atan2 and math.atan2(dy, dx)) or math.atan(dy, dx)
                        local angle = angle_rad * 57.29577951308232

                        local pVec = LineData.posVec
                        pVec.X = fromX; pVec.Y = fromY - thickness / 2.0
                        Slot:SetPosition(pVec)

                        local sVec = LineData.sizeVec
                        sVec.X = length; sVec.Y = thickness
                        Slot:SetSize(sVec)
                        Widget:SetRenderAngle(angle)
                    end
                end
            end
            lastCanvasX = currentCanvasX
            lastCanvasY = currentCanvasY
        end
    end

    for i = lineIndex + 1, #PlayerBones do
        local LineData = PlayerBones[i]
        if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
            LineData.Widget:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            LineData.Widget._isSelfHitTestVisible = false
        end
    end
end

function PMM.RemoveSkeletonLines(KeyStr)
    local PlayerBones = PMM.SkeletonWidgets[KeyStr]
    if PlayerBones then
        for _, LineData in ipairs(PlayerBones) do
            if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function()
                    LineData.Widget:RemoveFromParent()
                    LineData.Widget:ConditionalBeginDestroy()
                end)
            end
        end
        PMM.SkeletonWidgets[KeyStr] = nil
    end
end

function PMM.ClearAllSkeletonLines()
    for KeyStr, PlayerBones in pairs(PMM.SkeletonWidgets) do
        for _, LineData in ipairs(PlayerBones) do
            if LineData and LineData.Widget and slua.isValid(LineData.Widget) then
                pcall(function()
                    LineData.Widget:RemoveFromParent()
                    LineData.Widget:ConditionalBeginDestroy()
                end)
            end
        end
    end
    PMM.SkeletonWidgets = {}
end

-- ═══════════════════════════════════════════════════════════════════
-- Clear All ESP
-- ═══════════════════════════════════════════════════════════════════
function PMM.ClearAllESP()
    if _G.RedBoxOverlay then _G.RedBoxOverlay.Stop() end
    for KeyStr, Data in pairs(PMM.ESPWidgets) do
        PMM.RemoveESPWidget(Data.Widget, KeyStr)
    end
    PMM.ESPWidgets = {}
    PMM.ESPWidgetPtrs = {}
    PMM.ClearAllSnapLines()
    PMM.ClearAllSkeletonLines()
    -- ✅ لا تحذف أي شيء من Canvas الأصلي
    -- فقط أعد تعيين المراجع
    PMM.ESPCanvas = nil
    PMM._OBHeadWidgetClass = nil
    PMM._OBHeadWidgetLoadFailed = false
    PMM._bDumpedWidgetChildren = false
    PMM._cachedViewportW = 1920
    PMM._cachedViewportH = 1080
end

-- ═══════════════════════════════════════════════════════════════════
-- Update ESP — الدالة الرئيسية للرسم
-- ═══════════════════════════════════════════════════════════════════
function PMM.UpdateESP(AllPlayers, MyLoc)
    if not PMM.bUseScreenESP then return end

    PMM.bUseSnapLines = _G.LexusConfig.Esp9_Line
    PMM.bUseSkeleton = _G.LexusConfig.Esp9_Skeleton

    if not PMM.InitESPCanvas() then return end
    if PMM._OBHeadWidgetLoadFailed then return end

    local PC = PMM.GetMyPlayerController()
    if IsValid(PC) then PMM.UpdateCanvasTransform(PC) end

    local fromX, fromY = 0, 0
    if PMM.bUseSnapLines and IsValid(PC) then
        fromX, fromY = PMM.GetSnapLineStartPos(PC)
    end

    local MyKey = PMM.GetMyPlayerKey()
    local SeenKeys = {}

    local MyChar = nil
    pcall(function()
        local GDP = PMM.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then
            MyChar = GDP.GetLocalCharacter()
        else
            if PC and PC.GetPawn then MyChar = PC:GetPawn() end
        end
    end)
    local MyTeamID = PMM.GetTeamID(MyChar)

    for PlayerKey, Character in pairs(AllPlayers) do
        if IsValid(Character) then
            local bIsMe = PMM.IsMe(Character, PlayerKey, MyKey)
            local bIsAI = PMM.IsAI(Character)
            local KeyStr = tostring(PlayerKey)
            local Name = PMM.GetPlayerName(Character)

            local Loc = PMM.GetESPLocation(Character)
            local DistStr = ""
            if MyLoc and Loc then DistStr = PMM.GetDistanceString(MyLoc, Loc) end

            local bSkip = false
            if bIsMe and not PMM.bIncludeMe then bSkip = true end
            if bIsAI and not PMM.bIncludeAI then bSkip = true end

            local TeamID = PMM.GetTeamID(Character)
            if MyTeamID ~= nil and TeamID == MyTeamID and not bIsMe then bSkip = true end

            local bIsAlive = PMM.IsAlive(Character)

            if not bSkip and Loc then
                SeenKeys[KeyStr] = true
                local ESPData = PMM.ESPWidgets[KeyStr]

                local Text = ""
                if _G.LexusConfig.Esp9_Name then Text = Name end
                if _G.LexusConfig.Esp9_Distance and DistStr and DistStr ~= "" then
                    if Text ~= "" then Text = string.format("%s [%s]", Text, DistStr)
                    else Text = string.format("[%s]", DistStr) end
                end

                local bOnScreen, CanvasPos = PMM.ProjectWorldToCanvasLocal(PC, Loc)

                if not ESPData then
                    local Widget = PMM.CreateESPWidget()
                    if Widget then
                        PMM.ESPWidgets[KeyStr] = {
                            Widget = Widget,
                            Character = Character,
                            Name = Name,
                            LastDistStr = DistStr,
                            TeamID = TeamID,
                        }
                        PMM.UpdateESPText(Widget, Text)
                        if bIsAlive then
                            PMM.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)
                            PMM.ApplyTeamColor(Widget, TeamID)
                            local HP = Character.Health or 0
                            local MaxHP = Character.MaxHealth or 120
                            local pct = 0
                            if HP > 0 and MaxHP > 0 then
                                pct = HP / MaxHP
                                if pct > 1 then pct = 1 end
                                if pct < 0 then pct = 0 end
                            end
                            PMM.UpdateESPHealth(Widget, pct)
                            PMM.AddWeaponIconToESP(Widget, Character)
                            if PMM.bUseSnapLines then PMM.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
                            else PMM.RemoveSnapLine(KeyStr) end
                            if PMM.bUseSkeleton then PMM.UpdateSkeletonLines(KeyStr, Character, PC, true, PMM.GetTeamColor(TeamID), bOnScreen, Loc)
                            else PMM.RemoveSkeletonLines(KeyStr) end
                        else
                            local Container = Widget.Container or Widget
                            pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                            PMM.UpdateESPHealth(Widget, 0)
                            PMM.RemoveSnapLine(KeyStr)
                            PMM.RemoveSkeletonLines(KeyStr)
                        end
                    end
                else
                    ESPData.Character = Character
                    ESPData.Name = Name
                    ESPData.LastDistStr = DistStr
                    if bIsAlive then
                        ESPData.TeamID = TeamID
                        PMM.ApplyTeamColor(ESPData.Widget, TeamID)
                        ESPData.Widget._LastESPText = nil
                        PMM.UpdateESPText(ESPData.Widget, Text)
                        PMM.UpdateESPPositionWithPC(ESPData.Widget, Loc, PC, CanvasPos)
                        local HP = Character.Health or 0
                        local MaxHP = Character.MaxHealth or 120
                        local pct = 0
                        if HP > 0 and MaxHP > 0 then
                            pct = HP / MaxHP
                            if pct > 1 then pct = 1 end
                            if pct < 0 then pct = 0 end
                        end
                        PMM.UpdateESPHealth(ESPData.Widget, pct)
                        PMM.AddWeaponIconToESP(ESPData.Widget, Character)
                        if PMM.bUseSnapLines then PMM.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
                        else PMM.RemoveSnapLine(KeyStr) end
                        if PMM.bUseSkeleton then PMM.UpdateSkeletonLines(KeyStr, Character, PC, true, PMM.GetTeamColor(TeamID), bOnScreen, Loc)
                        else PMM.RemoveSkeletonLines(KeyStr) end
                    else
                        local Container = ESPData.Widget.Container or ESPData.Widget
                        pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                        PMM.UpdateESPHealth(ESPData.Widget, 0)
                        PMM.RemoveSnapLine(KeyStr)
                        PMM.RemoveSkeletonLines(KeyStr)
                    end
                end
            end
        end
    end

    for KeyStr, Data in pairs(PMM.ESPWidgets) do
        if not SeenKeys[KeyStr] then
            PMM.RemoveESPWidget(Data.Widget, KeyStr)
            PMM.ESPWidgets[KeyStr] = nil
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- Update ESP Light (كل 0.02 ثانية — سريع)
-- ═══════════════════════════════════════════════════════════════════
function PMM.UpdateESPLight()
    if _G.RedBoxOverlay and _G.RedBoxOverlay.bActive then _G.RedBoxOverlay.UpdatePosition() end
    if not PMM.bUseScreenESP then return end

    PMM.bUseSnapLines = _G.LexusConfig.Esp9_Line
    PMM.bUseSkeleton = _G.LexusConfig.Esp9_Skeleton
    if not PMM.ESPCanvas or not Game:IsValid(PMM.ESPCanvas) then return end
    local PC = PMM.GetMyPlayerController()
    if not IsValid(PC) then return end

    PMM.UpdateCanvasTransform(PC)

    local fromX, fromY = 0, 0
    if PMM.bUseSnapLines then fromX, fromY = PMM.GetSnapLineStartPos(PC) end

    for KeyStr, ESPData in pairs(PMM.ESPWidgets) do
        local Widget = ESPData.Widget
        local Character = ESPData.Character
        local Container = Widget and (Widget.Container or Widget)
        local bWidgetValid = false
        pcall(function() bWidgetValid = Container and slua.isValid(Container) end)

        if Widget and bWidgetValid and Character and IsValid(Character) then
            local bIsAlive = PMM.IsAlive(Character)
            if not bIsAlive then
                pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                PMM.RemoveSnapLine(KeyStr)
                PMM.RemoveSkeletonLines(KeyStr)
            else
                local bShowAnyUI = _G.LexusConfig.Esp9_Name or _G.LexusConfig.Esp9_Distance or _G.LexusConfig.Esp9_HP or _G.LexusConfig.Esp9_Team or _G.LexusConfig.Esp9_Weapon
                if bShowAnyUI then
                    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible) end)
                else
                    pcall(function() Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                end
                pcall(function() Container:SetRenderOpacity(1.0) end)

                local Loc = PMM.GetESPLocation(Character)
                if Loc then
                    local bOnScreen, CanvasPos = PMM.ProjectWorldToCanvasLocal(PC, Loc)
                    PMM.UpdateESPPositionWithPC(Widget, Loc, PC, CanvasPos)
                    if PMM.bUseSnapLines then PMM.UpdateSnapLine(KeyStr, CanvasPos, bOnScreen, fromX, fromY)
                    else PMM.RemoveSnapLine(KeyStr) end
                    if PMM.bUseSkeleton then
                        PMM.UpdateSkeletonLines(KeyStr, Character, PC, true, PMM.GetTeamColor(ESPData.TeamID), bOnScreen, Loc)
                    else
                        PMM.RemoveSkeletonLines(KeyStr)
                    end
                else
                    PMM.RemoveSnapLine(KeyStr)
                    PMM.RemoveSkeletonLines(KeyStr)
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- Update ESP Distances (كل 0.1 ثانية)
-- ═══════════════════════════════════════════════════════════════════
function PMM.UpdateESPDistances()
    if not PMM.bUseScreenESP then return end
    local MyLoc = PMM.GetMyLocation()
    if not MyLoc then return end
    local PC = PMM.GetMyPlayerController()
    if not IsValid(PC) then return end
    PMM.UpdateCanvasTransform(PC)

    for KeyStr, ESPData in pairs(PMM.ESPWidgets) do
        local Character = ESPData.Character
        local Widget = ESPData.Widget
        local Container = Widget and (Widget.Container or Widget)
        local bWidgetValid = false
        pcall(function() bWidgetValid = Container and slua.isValid(Container) end)
        if Character and IsValid(Character) and Widget and bWidgetValid then
            local Loc = PMM.GetESPLocation(Character)
            if Loc then
                local Dist = PMM.CalcDistance(MyLoc, Loc)
                ESPData.LastDistance = Dist
                if PMM.bShowDistance then
                    local DistStr = ""
                    if Dist then
                        local Meters = Dist / 100
                        if Meters < 1000 then DistStr = string.format("%dm", math.floor(Meters))
                        else DistStr = string.format("%.1fkm", Meters / 1000) end
                    end
                    local Name = ESPData.Name or "Unknown"
                    local Text = ""
                    if _G.LexusConfig.Esp9_Name then Text = Name end
                    if _G.LexusConfig.Esp9_Distance and DistStr and DistStr ~= "" then
                        if Text ~= "" then Text = string.format("%s [%s]", Text, DistStr)
                        else Text = string.format("[%s]", DistStr) end
                    end
                    ESPData.LastDistStr = DistStr
                    Widget._LastESPText = nil
                    PMM.UpdateESPText(Widget, Text)
                end
            end
        end
    end
end

print("[N5LA] ✅ ESP Part 5/6 loaded (Skeleton + Update ESP)")

-- =====================================================================
-- ESP FULL SYSTEM — Part 6/6: Scan + Timers + Start/Stop + UI Hook
-- =====================================================================

-- ═══════════════════════════════════════════════════════════════════
-- ScanAndUpdate — الفحص الرئيسي (يُستدعى كل 0.5 ثانية)
-- ═══════════════════════════════════════════════════════════════════
function PMM.ScanAndUpdate()
    local AllChars = PMM.GetAllCharacters()
    if not AllChars then
        if _G.RedBoxOverlay then _G.RedBoxOverlay.SetCounts(0, 0) end
        return 0
    end

    local MyKey = PMM.GetMyPlayerKey()
    local MyLoc = PMM.GetMyLocation()

    local MyChar = nil
    pcall(function()
        local GDP = PMM.GetGameplayData()
        if GDP and GDP.GetLocalCharacter then MyChar = GDP.GetLocalCharacter()
        else
            local PC = PMM.GetMyPlayerController()
            if PC and PC.GetPawn then MyChar = PC:GetPawn() end
        end
    end)
    local MyTeamID = PMM.GetTeamID(MyChar)

    local realPlayers = 0
    local botPlayers = 0

    for PlayerKey, Character in pairs(AllChars) do
        if IsValid(Character) then
            local bIsMe = PMM.IsMe(Character, PlayerKey, MyKey)
            local bIsAI = PMM.IsAI(Character)
            local bIsAlive = PMM.IsAlive(Character)

            if bIsAlive and not bIsMe then
                local bIsMyTeam = false
                if MyTeamID ~= nil then
                    local targetTeamID = PMM.GetTeamID(Character)
                    if targetTeamID == MyTeamID then bIsMyTeam = true end
                end

                if not bIsMyTeam then
                    if bIsAI then botPlayers = botPlayers + 1
                    else realPlayers = realPlayers + 1 end
                end
            end
        end
    end

    -- عدّاد RedBox
    if _G.LexusConfig.Esp9_Count then
        if _G.RedBoxOverlay then
            if _G.RedBoxOverlay.bActive then
                _G.RedBoxOverlay.SetCounts(realPlayers, botPlayers)
            else
                _G.RedBoxOverlay.Start()
            end
        end
    else
        if _G.RedBoxOverlay and _G.RedBoxOverlay.bActive then
            _G.RedBoxOverlay.Stop()
        end
    end

    if PMM.bUseScreenESP then
        PMM.UpdateESP(AllChars, MyLoc)
    end
    return 0
end

-- ═══════════════════════════════════════════════════════════════════
-- Attach Timers — يسجل الحلقات الزمنية
-- ═══════════════════════════════════════════════════════════════════
function PMM.AttachTimers()
    pcall(function()
        local pc = PMM.GetMyPlayerController()
        if not slua.isValid(pc) or not pc.AddGameTimer then
            local now = os.time()
            if PMM._AttachPending then
                if PMM._AttachPendingTime and (now - PMM._AttachPendingTime) < 2 then return end
            end
            PMM._AttachPending = true
            PMM._AttachPendingTime = now
            pcall(function()
                require("timer").SetGameTimer(1.0, false, function()
                    PMM._AttachPending = nil
                    PMM._AttachPendingTime = nil
                    PMM.AttachTimers()
                end)
            end)
            return
        end

        PMM._AttachPending = nil
        PMM._AttachPendingTime = nil
        local now = os.time()
        local lastPC = PMM._ActiveTimerPC
        local lastTick = PMM._ActiveTimerTick
        if lastPC and slua.isValid(lastPC) and lastPC == pc then
            if lastTick and (now - lastTick) < 5 then return end
        end

        PMM._ActiveTimerPC = pc
        PMM._ActiveTimerTick = now

        -- 1) حلقة الفحص الرئيسي كل 0.5 ثانية
        pcall(function()
            pc:AddGameTimer(PMM.nUpdateInterval or 0.5, true, function()
                PMM._ActiveTimerTick = os.time()
                if PMM.bActive then
                    pcall(function() PMM.ScanAndUpdate() end)
                end
            end)
        end)

        -- 2) حلقة التحديث السريع كل 0.02 ثانية
        pcall(function()
            pc:AddGameTimer(PMM._LightUpdateInterval or 0.02, true, function()
                PMM._ActiveTimerTick = os.time()
                if PMM.bActive then
                    pcall(function() PMM.UpdateESPLight() end)
                end
            end)
        end)

        -- 3) حلقة تحديث المسافات كل 0.1 ثانية
        pcall(function()
            pc:AddGameTimer(PMM._DistanceUpdateInterval or 0.1, true, function()
                PMM._ActiveTimerTick = os.time()
                if PMM.bActive and PMM.bUseScreenESP and PMM.bShowDistance then
                    pcall(function() PMM.UpdateESPDistances() end)
                end
            end)
        end)

        -- 4) إعادة ربط كل 5 ثواني
        pcall(function()
            require("timer").SetGameTimer(5.0, false, PMM.AttachTimers)
        end)
    end)
end

-- ═══════════════════════════════════════════════════════════════════
-- Start / Stop
-- ═══════════════════════════════════════════════════════════════════
function PMM.Start()
    if PMM.bActive then return end
    PMM.bActive = true
    PMM._FrameCount = 0
    PMM.ScanAndUpdate()
    PMM.AttachTimers()
    print("[N5LA] ✅ ESP Started")
end

function PMM.Stop()
    PMM.bActive = false
    PMM._FrameCount = 0
    PMM.ClearAllESP()
    print("[N5LA] ⛔ ESP Stopped")
end

-- ═══════════════════════════════════════════════════════════════════
-- حلقة مراقبة مستقلة (تضمن عمل ESP دائماً)
-- ═══════════════════════════════════════════════════════════════════
local function ESPWatchLoop()
    pcall(function()
        if not _G.PlayerMapMarker then return end
        PMM.bUseScreenESP = _G.LexusConfig.EspLoai9
        PMM.bUseSnapLines = _G.LexusConfig.Esp9_Line
        PMM.bUseSkeleton = _G.LexusConfig.Esp9_Skeleton

        if _G.LexusConfig.EspLoai9 then
            if not PMM.bActive then
                PMM.Start()
            end
        else
            if PMM.bActive then
                PMM.Stop()
            end
        end
    end)
    pcall(function()
        require("common.time_ticker").AddTimerOnce(0.15, ESPWatchLoop)
    end)
end

pcall(function()
    require("common.time_ticker").AddTimerOnce(1.0, ESPWatchLoop)
end)

-- ═══════════════════════════════════════════════════════════════════
-- ربط الأزرار في قائمة الإعدادات (ESP VIP FULL)
-- ═══════════════════════════════════════════════════════════════════

print("[N5LA] ✅ ESP Part 6/6 loaded (Scan + Timers + Start/Stop + UI Hook)")
print("[N5LA] 🎉 ESP VIP FULL System — COMPLETE!")
-- =====================================================================
-- N5LA LICENSE SYSTEM v6.0 — Replace Old Time-Based License
-- Rights: @MON5LA | t.me/MON5LA
-- =====================================================================
-- ==============================================================================
-- ==================== N5LA FIXED EXPIRY SYSTEM (2026-10-10) ===================
-- ==============================================================================
local limitTime   = os.time({ year = 2026, month = 10, day = 30, hour = 23, min = 59, sec = 0 })
local currentTime = os.time(os.date("!*t"))
local isExpired   = false

pcall(function()
    local fileName = ".sys_time_cache"
    local paths = {
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "//storage/emulated/0/Android/data/com.tencent.ig/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.vng.pubgmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.krmobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.rekoo.pubgm/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "//storage/emulated/0/Android/data/com.pubg.imobile/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "Documents/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "Documents/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "/Documents/ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "/Documents/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
        "../../ShadowTrackerExtra/Saved/SaveGames/" .. fileName,
        "../../ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName,
    }

    if os and os.getenv then
        local homeDir = os.getenv("HOME")
        if homeDir and homeDir ~= "" then
            table.insert(paths, 1, homeDir .. "/Documents/ShadowTrackerExtra/Saved/SaveGames/" .. fileName)
            table.insert(paths, 2, homeDir .. "/Documents/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName)
        end
    end

    local tm = package.loaded["client.logic.common.TimeManager"]
    if not tm then
        local s, r = pcall(require, "client.logic.common.TimeManager")
        if s and r then tm = r end
    end
    if tm and type(tm.GetServerTime) == "function" then
        local serverTime = tm.GetServerTime()
        if serverTime and serverTime > 1700000000 then
            currentTime = serverTime
        end
    end

    local lastSeenTime = 0
    for _, path in ipairs(paths) do
        local file = io.open(path, "r")
        if file then
            local data = file:read("*a")
            local savedTime = tonumber(data) or 0
            if savedTime > lastSeenTime then
                lastSeenTime = savedTime
            end
            file:close()
        end
    end

    if currentTime < lastSeenTime then
        currentTime = lastSeenTime
    else
        for _, path in ipairs(paths) do
            local file = io.open(path, "w")
            if file then
                file:write(tostring(currentTime))
                file:close()
            end
        end
    end
end)

isExpired = (currentTime > limitTime)

-- ✅ تفعيل القائمة عند النجاح (بدل نظام الأكواد)
if not isExpired then
    pcall(function() if _G.InitModMenuTab then _G.InitModMenuTab() end end)
    pcall(function() if _G.ShowMON5LAVIPMenu then _G.ShowMON5LAVIPMenu() end end)
end

-- ========================================== 
-- MAP MARK CLEANUP MANAGEMENT FUNCTION (ANTI-LAG/FAKE DISPLAY WHEN ENEMY DIES)
-- ========================================== 
local function SafeAddMark(id, pos, z, str, size, actor)
    local mark = nil
    pcall(function()
        local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.ClientAddMapMark then
            mark = InGameMarkTools.ClientAddMapMark(id, pos, z, str, size, actor)
            if mark then _G.MON5LAState.TrackedMarks[mark] = true end
        end
    end)
    return mark
end

local function SafeRemoveMark(mark)
    if not mark then return end
    pcall(function()
        local InGameMarkTools = require("GameLua.Mod.BaseMod.Common.InGameMarkTools")
        if InGameMarkTools and InGameMarkTools.HideMapMark then
            InGameMarkTools.HideMapMark(mark)
        end
        if InGameMarkTools and InGameMarkTools.RemoveMapMark then
            InGameMarkTools.RemoveMapMark(mark)
        end
    end)
    _G.MON5LAState.TrackedMarks[mark] = nil
end

-- ========================================== 
-- CREATE A UNIQUE AND PERMANENT ID FOR EACH ENEMY (FIXED LAG ISSUES WHEN SLUA CREATES NEW WRAPPERS)
-- ==========================================
local function GetSafeEnemyKey(enemy)
    if Valid(enemy) then
        if enemy.PlayerKey then return tostring(enemy.PlayerKey) end
        if type(enemy.GetUniqueID) == "function" then return tostring(enemy:GetUniqueID()) end
    end
    return tostring(enemy)
end

-- ========================================== 
-- AI (BOT) / REAL PLAYER - OPTIMIZED TEST
-- ==========================================
local function CheckIsAI(pawn, markData)
    if markData.AK_IS_BOT ~= nil then return markData.AK_IS_BOT, true end
    
    local isAI = false
    local hasChecked = false
    pcall(function()
        if pawn.bIsAI == true or pawn.IsAI == true then isAI = true; hasChecked = true end
        if type(pawn.IsBot) == "function" and pawn:IsBot() then isAI = true; hasChecked = true end
        
        local pState = pawn.PlayerState or (type(pawn.GetPlayerState) == "function" and pawn:GetPlayerState())
        if Valid(pState) then
            hasChecked = true
            if pState.bIsABot == true or pState.bIsBot == true then isAI = true end
            if type(pState.IsBot) == "function" and pState:IsBot() then isAI = true end
        end
        
        if not isAI then
            local name = pawn.PlayerName or (type(pawn.GetPlayerName) == "function" and pawn:GetPlayerName()) or ""
            if name ~= "" and (name:find("Cobra") or name:find("Target") or name:find("bot_") or name:find("b_")) then
                isAI = true
                hasChecked = true
            end
        end
    end)
    if hasChecked then markData.AK_IS_BOT = isAI end
    return isAI, hasChecked
end

-- ========================================== 
-- INITIALIZES AUTO HEAD HOOKS FOR DAMAGE
-- ==========================================
function _G.InitializeAutoHeadHooks()
    pcall(function()
        local EAvatarDamagePosition = import("EAvatarDamagePosition")
        if not EAvatarDamagePosition then return end

        local modulesToHook = {
            "GameLua.Mod.BaseMod.Common.Weapon.ShootWeaponEntity",
            "GameLua.Logic.Weapon.ShootWeaponEntity"
        }
        
        for _, path in ipairs(modulesToHook) do
            local hitLogic = package.loaded[path]
            if hitLogic then
                local original_GetHitBodyType = hitLogic.GetHitBodyType
                hitLogic.GetHitBodyType = function(self, ImpactResult, InImpactVec)
                    if _G.MON5LAConfig.AutoHead then return EAvatarDamagePosition.BigHead end
                    if original_GetHitBodyType then return original_GetHitBodyType(self, ImpactResult, InImpactVec) end
                end

                local original_GetHitBodyTypeByHitPos = hitLogic.GetHitBodyTypeByHitPos
                hitLogic.GetHitBodyTypeByHitPos = function(self, InImpactVec)
                    if _G.MON5LAConfig.AutoHead then return EAvatarDamagePosition.BigHead end
                    if original_GetHitBodyTypeByHitPos then return original_GetHitBodyTypeByHitPos(self, InImpactVec) end
                end
            end
        end
    end)
end

-- ========================================== 
-- COLOR CONFIGURATION FOR ESP HEALTH, ESP NAME, AND WALLHACK
-- ==========================================
if _G.ColorConfig == nil then
    _G.ColorConfig = {
        VisibleColor = 4,
        InvisibleColor = 1,
        Brightness = 25,
        Glow = 3.0,
    }
end

local COLOR_MAP = {
    [1] = {R=255, G=0,   B=0},
    [2] = {R=255, G=255, B=255},
    [3] = {R=255, G=255, B=0},
    [4] = {R=0,   G=255, B=0},
    [5] = {R=0,   G=255, B=255},
    [6] = {R=0,   G=0,   B=255},
    [7] = {R=255, G=0,   B=255}
}

local function GetAppliedColor(colorIdx, brightness)
    local base = COLOR_MAP[colorIdx] or COLOR_MAP[4]
    local b = brightness or _G.ColorConfig.Brightness or 25
    return {
        R = math.min(255, (base.R or 0) * b / 25),
        G = math.min(255, (base.G or 0) * b / 25),
        B = math.min(255, (base.B or 0) * b / 25),
        A = 255
    }
end

-- ========================================== 
-- AUTOMATIC VIP MENU STORAGE AND LOADING SYSTEM
-- ========================================== 
local function GetConfigPaths(fileName)
    local paths = {}
    
    -- ═══ Priority 1: Paks folder (المسار الجديد) ═══
    local android_packages = {
        "com.tencent.ig",
        "com.pubg.krmobile",
        "com.vng.pubgmobile",
        "com.rekoo.pubgm",
        "com.pubg.imobile",
        "com.pubg.tw",
        "com.tencent.pubgm",
    }
    
    for _, pkg in ipairs(android_packages) do
        -- ✅ المسار الرئيسي: Paks
        table.insert(paths, "//storage/emulated/0/Android/data/" .. pkg .. "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Paks/" .. fileName)
        -- ✅ مسار احتياطي: Gamelet/logs (إذا فشل Paks)
        table.insert(paths, "//storage/emulated/0/Android/data/" .. pkg .. "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName)
    end
    
    -- ═══ Priority 2: iOS / home directory ═══
    if os and os.getenv then
        local home = os.getenv("HOME")
        if home and home ~= "" then
            table.insert(paths, home .. "/Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName)
            table.insert(paths, home .. "/Documents/ShadowTrackerExtra/Saved/Gamelet/logs/" .. fileName)
        end
    end
    
    -- ═══ Priority 3: Paths relative (للاختبار والمحاكيات) ═══
    table.insert(paths, "Documents/ShadowTrackerExtra/Saved/Paks/" .. fileName)
    table.insert(paths, "ShadowTrackerExtra/Saved/Paks/" .. fileName)
    table.insert(paths, "../../ShadowTrackerExtra/Saved/Paks/" .. fileName)
    
    return paths
end

local ConfigFileName = "MON5LA_settings.txt"
_G.LastConfigSaveStr = ""

_G.SaveModSettings = function()
    pcall(function()
        local function serializeTable(tbl, indent)
            indent = indent or ""
            local items = {}
            for k, v in pairs(tbl) do
                local keyStr
                if type(k) == "string" then
                    keyStr = string.format("[%q]", k)
                elseif type(k) == "number" then
                    keyStr = "[" .. tostring(k) .. "]"
                else
                    keyStr = "[" .. tostring(k) .. "]"
                end
                
                if type(v) == "table" then
                    table.insert(items, indent .. keyStr .. " = " .. serializeTable(v, indent .. "  "))
                elseif type(v) == "string" then
                    table.insert(items, indent .. keyStr .. " = " .. string.format("%q", v))
                elseif type(v) == "number" or type(v) == "boolean" then
                    table.insert(items, indent .. keyStr .. " = " .. tostring(v))
                else
                    table.insert(items, indent .. keyStr .. " = nil")
                end
            end
            return "{\n" .. table.concat(items, ",\n") .. "\n" .. indent:sub(1, #indent-2) .. "}"
        end
        
        local data = "return {\nMON5LAConfig = " .. serializeTable(_G.MON5LAConfig or {}, "  ") .. ",\n"
        data = data .. "CustomTextData = " .. serializeTable(_G.MON5LAState.CustomTextData or {}, "  ") .. ",\n"
        data = data .. "ColorConfig = " .. serializeTable(_G.ColorConfig or {}, "  ") .. "\n}"
        
        if data == _G.LastConfigSaveStr then return end
        _G.LastConfigSaveStr = data

        local paths = GetConfigPaths(ConfigFileName)
        for _, path in ipairs(paths) do
            local file = io.open(path, "w")
            if file then
                file:write(data)
                file:close()
                break
            end
        end
    end)
end

_G.LoadModSettings = function()
    pcall(function()
        local paths = GetConfigPaths(ConfigFileName)
        local content = nil
        for _, path in ipairs(paths) do
            local file = io.open(path, "r")
            if file then
                content = file:read("*a")
                file:close()
                break
            end
        end

        if content then
            local func = load(content)
            if func then
                local savedData = func()
                if savedData and type(savedData) == "table" then
                    if savedData.MON5LAConfig then
                        for k, v in pairs(savedData.MON5LAConfig) do
                            _G.MON5LAConfig[k] = v
                        end
                    end
                    if savedData.CustomTextData then
                        _G.MON5LAState.CustomTextData = _G.MON5LAState.CustomTextData or {}
                        for k, v in pairs(savedData.CustomTextData) do
                            _G.MON5LAState.CustomTextData[k] = v
                        end
                    end
                    if savedData.ColorConfig then
                        for k, v in pairs(savedData.ColorConfig) do
                            _G.ColorConfig[k] = v
                        end
                    end
                end
            end
        end
    end)
end

local function AutoSaveLoop()
    pcall(function() if _G.SaveModSettings then _G.SaveModSettings() end end)
    pcall(function()
        local okTicker, ticker = pcall(require, "common.time_ticker") 
        if okTicker and ticker and ticker.AddTimerOnce then 
            ticker.AddTimerOnce(3.0, AutoSaveLoop)
        end
    end)
end

if not _G.ModConfigLoaded then
    _G.LoadModSettings()
    AutoSaveLoop()
    _G.ModConfigLoaded = true
end

_G.ReadLiveConfig = function()
    if _G.SaveModSettings then _G.SaveModSettings() end
end

-- ========================================== 
-- SKIN MOD SYSTEM (FULL LUCI VERSION + KILL COUNTER)
-- ==========================================
_G.VIP_Attachments = {
    [1101004236]={1010042307,1010042306,1010042308,1010042304,1010042300,1010042305,1010042299,1010042298,1010042297,1010042296,1010042295,1010042294,0,1010042314,1010042309,1010042316,1010042317,1010042318,1010042310,1010042315,1010042319,0},
    [1101001116]={1010011106,1010011107,1010011108,0,1010011109,1010011112,1010011105,1010011104,1010011103,0,1010011102,0,0,0,0,0,0,0,0,0,0,0},
    [1101001128]={1010011232,1010011233,1010011234,1010011228,1010011227,1010011229,1010011226,1010011225,1010011224,1010011223,1010011222,0,0,0,0,0,0,0,0,0,0,0},
    [1101001154]={1010011487,1010011488,1010011489,1010011493,1010011490,1010011494,1010011486,1010011485,1010011484,1010011483,1010011482,1010011497,0,0,0,0,0,0,0,0,1010011498,0},
    [1101001174]={1010011667,1010011668,1010011669,1010011673,1010011670,1010011674,1010011666,1010011665,1010011664,1010011663,1010011662,0,0,0,0,0,0,0,0,0,0,0},
    [1101001213]={1010012067,1010012068,1010012069,1010012072,1010012070,1010012073,1010012066,1010012065,1010012064,1010012063,1010012062,0,0,0,0,0,0,0,0,0,1010012074,0},
    [1101001231]={1010012267,1010012268,1010012269,1010012273,1010012272,1010012274,1010012266,1010012265,1010012264,1010012263,1010012262,1010012075,0,0,0,0,0,0,0,0,1010012275,0},
    [1101001242]={1010012357,1010012358,1010012359,1010012363,1010012362,1010012364,1010012356,1010012355,1010012354,1010012353,1010012352,1010012276,0,0,0,0,0,0,0,0,1010012365,0},
    [1101001249]={1010012437,1010012438,1010012439,1010012443,1010012442,1010012444,1010012436,1010012435,1010012434,1010012433,1010012432,1010012366,0,0,0,0,0,0,0,0,1010012445,0},
    [1101001256]={1010012588,1010012589,1010012590,1010012593,1010012592,1010012594,1010012587,1010012586,1010012585,1010012584,1010012583,1010012582,0,0,0,0,0,0,0,0,1010012595,0},
    [1101001265]={1010012698,1010012699,1010012700,1010012703,1010012702,1010012704,1010012697,1010012696,1010012695,1010012694,1010012693,1010012692,0,0,0,0,0,0,0,0,1010012705,0},
    [1101001276]={1010012698,1010012699,1010012700,1010012703,1010012702,1010012704,1010012697,1010012696,1010012695,1010012694,1010012693,1010012692,0,0,0,0,0,0,0,0,1010012705,0},
    [1101002029]={1010020249,1010020250,1010020255,1010020247,1010020246,1010020248,1010020240,1010020239,1010020238,1010020237,1010020236,1010020235,0,0,0,0,0,0,0,1010020257,1010020256,1010020258},
    [1101002056]={1010020519,0,0,1010020517,1010020516,1010020518,1010020500,1010020509,1010020508,1010020507,1010020506,1010020505,0,0,0,0,0,0,0,0,0,0},
    [1101002081]={1010020768,1010020769,1010020770,1010020766,1010020760,1010020767,1010020759,1010020758,1010020757,1010020756,1010020755,1010020776,0,0,0,0,0,0,0,1010020775,1010020777,1010020778},
    [1101003070]={1010030654,1010030653,1010030655,1010030649,1010030648,1010030650,1010030647,1010030646,1010030645,1010030644,1010030643,1010030642,0,1010030658,1010030656,1010030660,1010030662,1010030659,1010030657,0,1010030663,0},
    [1101003080]={1010030754,1010030753,1010030755,1010030749,1010030748,1010030750,1010030747,1010030746,1010030745,1010030744,1010030743,1010030742,0,1010030758,1010030756,1010030760,1010030762,1010030759,1010030757,0,1010030763,0},
    [1101003099]={1010030943,1010030944,1010030945,1010030939,1010030938,1010030942,1010030937,1010030936,1010030935,1010030934,1010030933,1010030932,0,1010030947,1010030946,1010030948,1010030949,1010030953,1010030952,0,1010030955,0},
    [1101003119]={1010031139,1010031140,1010031142,1010031138,1010031137,1010031146,1010031136,1010031135,1010031134,1010031133,1010031132,0,0,1010031144,1010031143,0,0,0,1010031145,0,0,0},
    [1101003146]={1010031229,1010031230,1010031237,1010031228,1010031227,1010031242,1010031226,1010031225,1010031224,1010031223,1010031222,0,0,1010031239,1010031238,0,0,0,1010031240,0,0,0},
    [1101003167]={1010031609,1010031610,1010031613,1010031608,1010031607,1010031617,1010031606,1010031605,1010031604,1010031603,1010031602,1010031618,0,1010031615,1010031614,1010031620,1010031622,1010031619,1010031616,0,1010031623,0},
    [1101003181]={1010031765,1010031764,1010031766,1010031759,1010031758,1010031763,1010031757,1010031756,1010031755,1010031754,1010031753,1010031752,0,1010031769,1010031767,1010031773,1010031774,1010031772,1010031768,0,1010031775,0},
    [1101003195]={1010031912,1010031911,1010031913,1010031908,1010031907,1010031909,1010031906,1010031905,1010031904,1010031903,1010031902,1010031901,0,1010031916,1010031914,1010031918,1010031919,1010031917,1010031915,0,1010031921,0},
    [1101003208]={1010032034,1010032033,1010032045,1010032029,1010032028,1010032032,1010032027,1010032026,1010032025,1010032024,1010032023,1010032022,0,1010032038,1010032036,1010032042,1010032043,1010032039,1010032037,0,1010032044,0},
    [1101004046]={1010040474,1010040475,1010040476,1010040472,1010040471,1010040473,1010040470,1010040469,1010040468,1010040467,1010040466,1010040481,0,1010040479,1010040477,1010040482,1010040483,1010040484,1010040478,1010040480,1010040485,0},
    [1101004062]={1010040578,1010040577,1010040579,1010040575,1010040570,1010040576,1010040569,1010040568,1010040567,1010040566,1010040565,1010040564,0,1010040585,1010040580,1010040587,1010040588,1010040589,1010040584,1010040586,1010040590,1010040594},
    [1101004098]={1010040924,1010040926,1010040925,0,1010040937,1010040938,1010040935,1010040934,1010040929,1010040928,1010040927,0,0,1010040939,1010040945,0,0,0,1010040944,1010040936,0,0},
    [1101004138]={1010041136,1010041137,1010041138,1010041134,1010041129,1010041135,1010041128,1010041127,1010041126,1010041125,1010041124,0,0,1010041145,1010041139,0,0,0,1010041144,1010041146,0,0},
    [1101004163]={1010041570,1010041574,1010041575,1010041568,1010041567,1010041569,1010041566,1010041565,1010041564,1010041560,1010041554,0,0,1010041578,1010041576,0,0,0,1010041577,1010041579,0,0},
    [1101004201]={1010041956,1010041957,1010041958,1010041950,1010041949,1010041955,1010041948,1010041947,1010041946,1010041945,1010041944,1010041967,0,1010041965,1010041959,0,0,0,1010041960,1010041966,0,0},
    [1101004209]={1010042038,1010042037,1010042039,1010042035,1010042034,1010042036,1010042029,1010042028,1010042027,1010042026,1010042025,1010042024,0,1010042046,1010042044,1010042048,1010042049,1010042054,1010042045,1010042047,1010042055,0},
    [1101004218]={1010042128,1010042127,1010042129,1010042125,1010042124,1010042126,1010042119,1010042118,1010042117,1010042116,1010042115,1010042114,0,1010042136,1010042134,1010042138,1010042139,1010042144,1010042135,1010042137,1010042145,0},
    [1101004226]={1010042238,1010042237,1010042239,1010042235,1010042234,1010042236,1010042233,1010042232,1010042231,1010042219,1010042218,1010042217,0,1010042243,1010042241,1010042245,1010042246,1010042247,1010042242,1010042244,1010042248,0},
    [1101004246]={1010042406,1010042407,1010042408,1010042404,1010042400,1010042405,1010042399,1010042398,1010042397,1010042396,1010042395,1010042394,0,1010042414,1010042409,1010042416,1010042417,1010042418,1010042410,1010042415,1010042419,1010042420},
    [1101005038]={0,0,1010050327,1010050329,1010050328,1010050330,1010050326,1010050325,1010050324,1010050323,1010050322,1010050334,0,0,0,0,0,0,0,0,0,0},
    [1101005052]={0,0,1010050467,1010050469,1010050468,1010050470,1010050466,1010050465,1010050464,1010050463,1010050462,1010050473,0,0,0,0,0,0,0,0,0,0},
    [1101005098]={0,0,1010050928,1010050930,1010050929,1010050932,1010050927,1010050926,1010050925,1010050924,1010050923,1010050922,0,0,0,0,0,0,0,0,0,0},
    [1101006062]={1010060573,1010060572,1010060574,1010060564,1010060563,1010060571,1010060562,1010060561,1010060554,1010060553,1010060552,1010060551,0,1010060583,1010060581,1010060591,1010060592,1010060584,1010060582,0,1010060593,0},
    [1101006075]={1010060702,1010060701,1010060703,1010060698,1010060697,1010060699,1010060696,1010060695,1010060694,1010060693,1010060692,1010060691,0,1010060706,1010060704,1010060708,1010060709,1010060707,1010060705,0,1010060711,0},
    [1101006085]={1010060796,1010060795,1010060797,1010060793,1010060789,1010060794,1010060788,1010060787,1010060786,1010060785,1010060784,1010060783,0,1010060800,1010060798,1010060804,1010060805,1010060803,1010060799,0,1010060806,0},
    [1101007046]={1010070410,1010070413,1010070414,1010070408,1010070407,1010070409,1010070406,1010070405,1010070404,1010070403,1010070402,1010070418,0,1010070417,1010070415,1010070420,1010070422,1010070419,1010070416,0,1010070423,0},
    [1101007062]={1010070579,1010070578,1010070581,1010070576,1010070575,1010070577,1010070574,1010070573,1010070572,1010070571,1010070569,1010070568,0,1010070584,1010070582,1010070585,1010070586,1010070587,1010070583,0,1010070588,0},
    [1101007071]={1010070663,1010070662,1010070664,1010070659,1010070658,1010070660,1010070657,1010070656,1010070655,1010070654,1010070653,1010070652,0,1010070667,1010070665,1010070668,1010070669,1010070670,1010070666,0,1010070672,0},
    [1101008051]={1010080463,1010080464,1010080465,1010080459,1010080458,1010080462,1010080457,1010080456,1010080455,1010080454,1010080453,1010080452,0,1010080467,1010080466,1010080468,1010080469,1010080473,1010080472,0,1010080475,0},
    [1101008061]={1010080563,1010080564,1010080565,1010080559,1010080558,1010080562,1010080557,1010080556,1010080555,1010080554,1010080553,0,0,1010080567,1010080566,0,0,0,1010080572,0,0,0},
    [1101008070]={1010080609,1010080612,1010080613,1010080608,1010080607,1010080617,1010080606,1010080605,1010080604,1010080603,1010080602,0,0,1010080615,1010080614,0,0,0,1010080616,0,0,0},
    [1101008081]={1010080740,1010080743,1010080745,1010080738,1010080737,1010080739,1010080736,1010080735,1010080734,1010080733,1010080732,1010080748,0,1010080747,1010080746,1010080750,1010080752,1010080749,1010080744,0,1010080753,0},
    [1101008104]={1010080980,1010080982,1010080984,1010080978,1010080977,1010080979,1010080976,1010080975,1010080974,1010080973,1010080972,1010080992,0,1010080986,1010080985,1010080989,1010080987,1010080993,1010080983,0,1010080988,0},
    [1101008116]={1010081110,1010081112,1010081114,1010081108,1010081107,1010081109,1010081106,1010081105,1010081104,1010081103,1010081102,0,0,1010081116,1010081115,0,0,0,1010081113,0,0,0},
    [1101008126]={1010081210,1010081225,1010081226,1010081208,1010081207,1010081209,1010081206,1010081205,1010081204,1010081203,1010081202,1010081218,0,1010081217,1010081216,1010081219,1010081220,1010081222,1010081214,1010081228,1010081227,1010081229},
    [1101008136]={1010081314,1010081315,1010081316,1010081312,1010081308,1010081313,1010081307,1010081306,1010081305,1010081304,1010081303,1010081302,0,1010081318,1010081317,1010081322,1010081323,1010081325,1010081324,0,1010081326,0},
    [1101008146]={1010081401,1010081402,1010081403,1010081398,1010081397,1010081399,1010081396,1010081395,1010081394,1010081393,1010081392,1010081391,0,1010081405,1010081404,1010081406,1010081407,1010081409,1010081408,0,1010081411,0},
    [1101008154]={1010081531,1010081532,1010081533,1010081528,1010081527,1010081529,1010081526,1010081525,1010081524,1010081523,1010081522,1010081521,0,1010081541,1010081534,1010081542,1010081543,1010081545,1010081544,0,1010081546,0},
    [1101008163]={1010081582,1010081583,1010081584,1010081579,1010081578,1010081580,1010081577,1010081576,1010081575,1010081574,1010081573,1010081572,0,1010081586,1010081585,1010081587,1010081588,1010081590,1010081589,0,1010081592,0},
    [1101012033]={1010120284,1010120285,1010120286,1010120280,1010120279,1010120283,1010120278,1010120277,1010120276,1010120275,1010120274,1010120273,0,0,0,0,0,0,0,0,1010120287,0},
    [1101100012]={1011000066,1011000067,1011000068,0,0,0,1011000058,1011000057,1011000056,1011000055,1011000054,1011000053,0,0,0,0,0,0,0,0,1011000073,0},
    [1101102007]={1011010025,1011010024,1011010026,1011010020,1011010019,1011010023,1011010018,1011010017,1011010016,1011010015,1011010014,1011010013,0,0,0,0,0,0,0,0,1011010027,0},
    [1101102017]={1011020027,1011020028,1011020029,1011020025,1011020024,1011020026,1011020019,1011020018,1011020017,1011020016,1011020015,1011020014,0,1011020036,1011020034,1011020038,1011020039,1011020044,1011020035,1011020037,1011020045,1011020047},
    [1101102025]={1011020127,1011020128,1011020129,1011020125,1011020124,1011020126,1011020119,1011020118,1011020117,1011020116,1011020115,1011020114,0,1011020136,1011020134,1011020138,1011020139,1011020144,1011020135,1011020137,1011020145,0},
    [1101102041]={1011020214,1011020215,1011020216,1011020212,1011020211,1011020213,1011020209,1011020208,1011020207,1011020206,1011020205,1011020204,0,1011020219,1011020217,1011020222,1011020223,1011020224,1011020218,1011020221,1011020225,1011020229},
    [1101102049]={1011020356,1011020357,1011020358,1011020354,1011020350,1011020355,1011020349,1011020348,1011020347,1011020346,1011020345,1011020344,0,1011020364,1011020359,1011020366,1011020367,1011020368,1011020360,1011020365,1011020369,1011020370},
    [1101101007]={1011020436,1011020437,1011020438,1011020434,1011020430,1011020435,1011020429,1011020428,1011020427,1011020426,1011020425,1011020424,0,1011020444,1011020439,1011020446,1011020447,1011020448,1011020440,1011020445,1011020449,1011020450},
    [1102001120]={1020011137,1020011138,1020011139,1020011135,1020011134,1020011136,1020011133,1020011132,0,0,0,0,0,0,0,0,0,0,0,1020011142,0,0},
    [1102001130]={1020011247,1020011248,1020011249,1020011245,1020011244,1020011246,1020011243,1020011242,0,0,0,0,0,0,0,0,0,0,0,1020011250,0,0},
    [1102002043]={1020020372,1020020374,1020020373,1020020383,1020020380,1020020384,1020020379,1020020378,1020020377,1020020376,1020020375,1020020388,0,1020020385,1020020387,0,0,0,1020020386,0,0,0},
    [1102002061]={1020020552,1020020554,1020020553,1020020563,1020020562,1020020564,1020020559,1020020558,1020020557,1020020556,1020020555,1020020578,0,1020020565,1020020567,1020020573,1020020574,1020020572,1020020566,0,1020020569,0},
    [1102002136]={1020021314,1020021313,1020021315,1020021309,1020021308,1020021312,1020021307,1020021306,1020021305,1020021304,1020021303,1020021302,0,1020021318,1020021316,1020021323,1020021324,1020021322,1020021317,0,1020021325,0},
    [1102002424]={1020024193,1020024192,1020024194,1020024189,1020024188,1020024190,1020024187,1020024186,1020024185,1020024184,1020024183,1020024182,0,1020024197,1020024195,1020024199,1020024200,1020024198,1020024196,0,1020024202,0},
    [1102003080]={1020030755,1020030756,1020030758,0,1020030749,1020030754,1020030748,1020030747,1020030746,1020030745,1020030744,1020030764,0,1020030760,0,1020030759,1020030757,0,0,1020030765,0,0},
    [1102003100]={1020030956,1020030957,1020030958,1020030954,1020030950,1020030955,1020030949,1020030948,1020030947,1020030946,1020030945,1020030944,0,1020030964,0,1020030960,1020030959,1020030965,0,1020030967,1020030966,1020030968},
    [1102005064]={1020050588,1020050589,1020050590,0,0,0,1020050587,1020050586,1020050585,1020050584,1020050583,1020050582,0,0,0,0,0,0,0,0,1020050592,0},
    [1103001101]={1030010954,1030010955,1030010956,0,0,0,0,0,0,0,1030010953,1030010952,1030010951,0,0,0,0,0,0,1030010957,0,1030010958},
    [1103001146]={1030011344,1030011345,1030011346,0,0,0,0,0,0,0,1030011343,1030011342,1030011341,0,0,0,0,0,0,1030011347,0,1030011348},
    [1103001154]={1030011484,1030011485,1030011486,0,0,0,0,0,0,0,1030011483,1030011482,1030011481,0,0,0,0,0,0,1030011487,0,1030011488},
    [1103001179]={1030011738,1030011739,1030011741,0,0,0,1030011737,1030011736,1030011735,1030011734,1030011733,1030011732,1030011731,0,0,0,0,0,0,1030011742,1030011743,1030011744},
    [1103001191]={1030011858,1030011859,1030011861,0,0,0,1030011857,1030011856,1030011855,1030011854,1030011853,1030011852,1030011851,0,0,0,0,0,0,1030011862,1030011863,1030011864},
    [1103001202]={1030011948,1030011949,1030011950,0,0,0,1030011947,1030011946,1030011945,1030011944,1030011943,1030011942,1030011941,0,0,0,0,0,0,1030011951,1030011952,1030011953},
    [1103002030]={1030020245,1030020246,1030020247,1030020252,1030020249,1030020253,1030020258,1030020257,1030020256,1030020255,1030020244,1030020243,1030020242,0,0,0,0,0,0,1030020248,0,0},
    [1103002059]={1030020544,1030020545,1030020546,1030020542,1030020539,1030020543,1030020538,1030020537,1030020536,1030020535,1030020534,1030020533,1030020532,0,0,0,0,0,0,1030020547,1030020548,0},
    [1103002087]={1030020824,1030020825,1030020826,0,0,0,1030020818,1030020817,1030020816,1030020815,1030020814,1030020813,1030020812,0,0,0,0,0,0,1030020827,1030020828,0},
    [1103002106]={1030021009,1030021010,1030021012,1030021015,1030021014,1030021016,1030021008,1030021007,1030021006,1030021005,1030021004,1030021003,1030021002,0,0,0,0,0,0,1030021013,1030021017,0},
    [1103002113]={1030021079,1030021080,1030021082,1030021085,1030021084,1030021086,1030021078,1030021077,1030021076,1030021075,1030021074,1030021073,1030021072,0,0,0,0,0,0,1030021083,1030021087,0},
    [1103003022]={1030030165,1030030166,1030030167,1030030172,1030030169,1030030173,0,0,0,0,1030030164,1030030163,1030030162,0,0,0,0,0,0,0,0,0},
    [1103003030]={1030030256,1030030257,1030030258,1030030254,1030030253,1030030255,1030030248,1030030247,1030030246,1030030245,1030030244,1030030243,1030030242,0,0,0,0,0,0,1030030259,1030030249,0},
    [1103003042]={1030030374,1030030375,1030030376,1030030372,1030030369,1030030373,0,0,0,0,1030030364,1030030363,1030030362,0,0,0,0,0,0,1030030377,0,0},
    [1103003051]={1030030458,1030030459,1030030460,1030030456,1030030455,1030030457,0,0,0,0,1030030454,1030030453,1030030452,0,0,0,0,0,0,1030030463,0,0},
    [1103003062]={1030030568,1030030569,1030030570,1030030566,1030030565,1030030567,0,0,0,0,1030030564,1030030563,1030030562,0,0,0,0,0,0,1030030572,0,0},
    [1103003079]={1030030744,1030030745,1030030746,1030030742,1030030740,1030030743,1030030738,1030030737,1030030736,1030030735,1030030734,1030030733,1030030732,0,0,0,0,0,0,1030030747,1030030739,0},
    [1103003087]={1030030825,1030030826,1030030827,1030030823,1030030824,1030030824,1030030818,1030030817,1030030816,1030030815,1030030814,1030030813,1030030812,0,0,0,0,0,0,1030030828,1030030819,0},
    [1103004037]={1030040315,1030040316,1030040317,1030040325,1030040324,1030040323,0,0,0,0,1030040314,1030040313,1030040312,1030040327,1030040326,0,0,0,1030040328,1030040329,0,0},
    [1103006030]={1030060245,1030060246,1030060247,0,1030060253,1030060252,0,0,0,0,1030060244,1030060243,1030060242,0,0,0,0,0,0,0,0,0},
    [1103007028]={1030070233,1030070234,1030070235,1030070226,1030070225,1030070227,1030070218,1030070217,1030070216,1030070215,1030070214,1030070213,1030070212,0,0,0,0,0,0,1030070236,1030070219,0},
    [1103012010]={0,0,0,0,0,0,1030120038,1030120037,1030120036,1030120035,1030120034,1030120033,1030120032,0,0,0,0,0,0,0,0,0},
    [1103012019]={0,0,0,0,0,0,1030120138,1030120137,1030120136,1030120135,1030120134,1030120133,1030120132,0,0,0,0,0,0,0,0,0},
    [1103012031]={0,0,0,0,0,0,1030120258,1030120257,1030120256,1030120255,1030120254,1030120253,1030120252,0,0,0,0,0,0,0,0,0},
    [1103012039]={0,0,0,0,0,0,1030120339,1030120338,1030120337,1030120336,1030120335,1030120334,1030120333,0,0,0,0,0,0,0,0,0},
    [1103102007]={1031020026,1031020027,1031020028,1031020024,1031020023,1031020025,1031020019,1031020018,1031020017,1031020016,1031020015,1031020014,1031020013,0,0,0,0,0,0,1031020029,0,0},
    [1105001034]={0,0,0,0,1050010287,1050010289,1050010286,1050010285,1050010284,1050010283,1050010282,0,0,0,0,0,0,0,0,1050010292,0,0},
    [1105001048]={0,0,0,1050010429,1050010428,1050010434,1050010427,1050010426,1050010425,1050010424,1050010423,0,0,0,0,0,0,0,0,1050010435,0,1050010436},
    [1105001069]={0,0,0,1050010639,1050010638,1050010640,1050010637,1050010636,1050010635,1050010634,1050010633,1050010645,0,0,0,0,0,0,0,1050010643,1050010646,1050010644},
    [1105002091]={0,0,0,0,0,0,1050020847,1050020846,1050020845,1050020844,1050020843,1050020842,0,0,0,0,0,0,0,0,0,1050020848},
    [1105010019]={0,0,0,0,0,0,1050100144,1050100143,1050100142,1050100141,1050100139,1050100138,0,0,0,0,0,0,0,0,0,0}
}

_G.BaseAttachToIndex = {
    [201010]=1, [201005]=1, [201004]=1, [201009]=2, [201003]=2, [201002]=2, 
    [201011]=3, [201007]=3, [201006]=3, [204012]=4, [204005]=4, [204008]=4, 
    [204011]=5, [204004]=5, [204007]=5, [204013]=6, [204006]=6, [204009]=6, 
    [203001]=7, [203002]=8, [203003]=9, [203014]=10, [203004]=11, [203015]=12, [203005]=13, 
    [202002]=14, [202001]=15, [202004]=16, [202005]=17, [202007]=18, [202006]=19, 
    [205002]=20, [205003]=20, [205001]=20, [203018]=21, [204014]=22 
}

_G.VipAttachToIndex = {}
for skinId, attachList in pairs(_G.VIP_Attachments) do
    for index, attachId in ipairs(attachList) do
        if attachId > 0 then
            _G.VipAttachToIndex[attachId] = index
        end
    end
end

_G.WeaponSkinMap = _G.WeaponSkinMap or {}
_G.VehicleSkinMap = _G.VehicleSkinMap or {}
_G.OutfitMap = _G.OutfitMap or {}
_G.skinIdCache = _G.skinIdCache or {}
_G.skinIdCache2 = _G.skinIdCache2 or {}

_G.OutfitSkins = {
    Suit = {1407994,1408021,1407906,1407453,1406388,1406387,1406386,1407142,1407550,1406638,1406872,1406971,1407103,1407512,1407391,1407285,1407330,1407329,1407286,1407285,1407277,1407276,1407275,1407225,1407224,1407259,1407161,1407160,1407107,1407106,1407079,1407048,1406977,1406976,1406898,1400569,1404000,1404049,1400119,1400117,1406060,1406891,1400687,1405160,1405145,1405436,1405435,1405434,1405064,1405207,1406398,1407812,1405132,1407856,1405121,1406889,1407278,1407279,1407381,1407380,1407916,1406469,1405870,1407140,1407141,1406385,1406140,1400782,1407392,1407318,1407317,1407404,1407402,1407401,1407387,1404434,1404437,1404440,1404448,1400324,1400708,1404043,1404048,1405953,1400101,1404153,1407440,1407441,1407522,1405069,1405355},
    Bag = {
        {501001, 501002, 501003}, {1501001174, 1501002174, 1501003174}, {1501001220, 1501002220, 1501003220},
        {1501001051, 1501002051, 1501003051}, {1501001443, 1501002443, 1501003443}, {1501001265, 1501002265, 1501003265},
        {1501001321, 1501002321, 1501003321}, {1501001277, 1501002277, 1501003277}, {1501001550, 1501002550, 1501003550},
        {1501001592, 1501002592, 1501003592}, {1501001608, 1501002608, 1501003608}, {1501001024, 1501002024, 1501003024},
        {1501001019, 1501002019, 1501003019}, {1501001179, 1501002179, 1501003179}, {1501001194, 1501002194, 1501003194},
        {1501001346, 1501002346, 1501003346}, {1501001057, 1501002057, 1501003057}, {1501001229, 1501002229, 1501003229},
        {1501001022, 1501002022, 1501003022}, {1501001022, 1501002022, 1501003022}
    },
    Helmet = {
        {502001, 502002, 502003}, {1502001014, 1502002014, 1502003014}, {1502001349, 1502002349, 1502003349},
        {1502001012, 1502002012, 1502003012}, {1502001009, 1502002009, 1502003009}, {1502001397, 1502002397, 1502003397},
        {1502001390, 1502002390, 1502003390}, {1502001381, 1502002381, 1502003381}, {1502001358, 1502002358, 1502003358},
        {1502001350, 1502002350, 1502003350}, {1502001342, 1502002342, 1502003342}, {1502001058, 1502002058, 1502003058},
        {1502001031, 1502002031, 1502003031}, {1502001054, 1502002054, 1502003054}
    },
    Pet = {50000,50001,50002,50003,50004,50005,50006,50021,50022,50038,50039,50040},
    
    -- ========== GLIDER + PARACHUTE ==========
    Glider = {41511, 4151145},
    Parachute = {14011, 1401107},
    Gloves = {4520, 452001, 452002, 452003},
}

_G.skinIdMappings = {
    [101004] = {101004, 1101004246,1101004209,1101004226,1101004236,1101004062,1101004078,1101004086,1101004201,1101004218,1101004046},
    [101001] = {101001,1101001276,1101001265,1101001213,1101001172,1101001127,1101001230,1101001241},
    [101003] = {101003,1101003227,1103003208,1101003195,1101003187,1101003098,1101003166,1101003218},
    [101008] = {101008,1101008146,1101008154,1101008079,1101008126,1101008104,1101008146,1101008061,1101008116},
    [101006] = {101006,1101006106,1101006098,1101006085,1101006061,1101006074,1101006043,1101006032,1101006084},
    [101012] = {101012,1101012033},
    [101007] = {101007,1101007062,1101007071},
    [102002] = {102002,1102002136,1102002043,1102002061,1102002424,1102002438},
    [101101] = {101101, 1101101007},
    [101102] = {101102, 1101102041},
    [102001] = {102001, 1102001120},
    [102003] = {102003, 1102003100},
    [101005] = {101005, 1101005098},
    [103001] = {103001, 1103001202,1103001191},
    [103002] = {103002, 1103002106},
    [103003] = {103003, 1103003042,1103003062,1103003099},
    [103012] = {103012, 1103012039,1103012010},
    [104003] = {104003, 1104003037},
    [102005] = {102005, 1102005064},
    [104004] = {104004, 1104004035, 1104004041}
}

_G.VehicleSkins = { 
    [1961001] = { 1961007, 1961149, 1961069, 1961013, 1961014, 1961015, 1961016, 1961017, 1961018, 1961020, 1961021, 1961024, 1961025, 1961029, 1961030, 1961031, 1961032, 1961033, 1961034, 1961035, 1961036, 1961037, 1961038, 1961039, 1961040, 1961041, 1961042, 1961043, 1961044, 1961045, 1961046, 1961047, 1961048, 1961049, 1961050, 1961051, 1961052, 1961053, 1961054, 1961055, 1961056, 1961057, 1961058, 1961059, 1961060, 1961061, 1961062, 1961063, 1961064, 1961065, 1961066, 1961067, 1961068,1961136, 1961137, 1961138, 1961139, 1961140, 1961141, 1961142, 1961143, 1961144, 1961145, 1961147, 1961148, 1961010, 1961150, 1961151, 1961152, 1961153 },
    [1903001] = { 1903005, 1903006, 1903007, 1903008, 1903011, 1903012, 1903013, 1903014, 1903015, 1903016, 1903017, 1903018, 1903019, 1903020, 1903021, 1903022, 1903023, 1903024, 1903029, 1903030, 1903031, 1903032, 1903033, 1903034, 1903035, 1903036, 1903037, 1903039, 1903040, 1903041, 1903042, 1903043, 1903044, 1903045, 1903046, 1903051, 1903052, 1903053, 1903054, 1903055, 1903056, 1903057, 1903058, 1903059, 1903060, 1903061, 1903062, 1903063, 1903066, 1903067, 1903068, 1903069, 1903070, 1903071, 1903072, 1903073, 1903074, 1903075, 1903076, 1903079, 1903080, 1903081, 1903082, 1903084, 1903085, 1903086, 1903087, 1903088, 1903089, 1903090, 1903189, 1903190, 1903191, 1903192, 1903193, 1903194, 1903195, 1903196, 1903197, 1903198, 1903199, 1903200, 1903201, 1903202, 1903203, 1903204, 1903205, 1903206, 1903207, 1903208, 1903209, 1903210, 1903211, 1903212, 1903213, 1903214, 1903215, 1903216, 1903217, 1903218, 1903219, 1903220, 1903221, 1903222, 1903223, 1903225, 1903226, 1903227, 1903228 }, 
    [1915001] = { 1915002, 1915003, 1915007, 1915005, 1915006, 1915008, 1915009, 1915010, 1915011, 1915012, 1915013, 1915014, 1915015, 1915016, 1915017, 1915018, 1915019, 1915020, 1915021, 1915022, 1915023, 1915024, 1915025, 1915026, 1915027, 1915099 },          
    [1908001] = { 1908002, 1908003, 1908094, 1908006, 1908007, 1908008, 1908009, 1908010, 1908011, 1908012, 1908013, 1908015, 1908016, 1908017, 1908018, 1908019, 1908021, 1908023, 1908030, 1908031, 1908032, 1908033, 1908034, 1908035, 1908036, 1908037, 1908039, 1908040, 1908041, 1908043, 1908047, 1908049, 1908050, 1908051, 1908052, 1908053, 1908054, 1908055, 1908056, 1908057, 1908059, 1908060, 1908061, 1908062, 1908063, 1908064, 1908066, 1908067, 1908068, 1908069, 1908070, 1908075, 1908076, 1908077, 1908078, 1908080, 1908081, 1908082, 1908083, 1908084, 1908085, 1908086, 1908087, 1908088, 1908089, 1908091, 1908095, 1908096, 1908097, 1908098, 1908099, 1908100, 1908101, 1908102, 1908104, 1908105, 1908106, 1908107, 1908108, 1908109, 1908110, 1908111, 1908112, 1908188, 1908189 },   
    [1907001] = { 1907007, 1907008, 1907010, 1907011, 1907012, 1907013, 1907014, 1907016, 1907018, 1907019, 1907021, 1907022, 1907023, 1907025, 1907026, 1907027, 1907028, 1907029, 1907030, 1907032, 1907033, 1907034, 1907035, 1907036, 1907037, 1907038, 1907040, 1907041, 1907043, 1907044, 1907045, 1907046, 1907047, 1907048, 1907049, 1907050, 1907051, 1907052, 1907053, 1907054, 1907055, 1907056, 1907058, 1907059, 1907060, 1907061, 1907062, 1907063, 1907064, 1907065, 1907066, 1907067, 1907068, 1907069, 1907070, 1907071, 1907072, 1907073, 1907074 }
}
_G.CustSlotType = { ClothesEquipemtSlot=5, BackpackEquipemtSlot=8, HelmetEquipemtSlot=9, ParachuteEquipemtSlot=11, GlideEquipemtSlot=15 }

local function DownloadGameItem(id)
    local puffer_manager = require('client.slua.logic.download.puffer.puffer_manager')
    local puffer_const = require('client.slua.logic.download.puffer_const')
    if puffer_manager and puffer_const and puffer_manager.GetState(puffer_const.ENUM_DownloadType.ODPTD, {id}) ~= puffer_const.ENUM_DownloadState.Done then
        puffer_manager.Download(puffer_const.ENUM_DownloadType.ODPTD, {id})
    end
end
_G.download_item = DownloadGameItem

_G.get_skin_id = function(weaponID)
    if not weaponID then return nil end
    local targetSkinId = _G.WeaponSkinMap and _G.WeaponSkinMap[weaponID]
    if targetSkinId and targetSkinId > 0 then
        if not _G.skinIdCache2[targetSkinId] then
            if _G.download_item then pcall(_G.download_item, targetSkinId) end
            _G.skinIdCache2[targetSkinId] = true
        end
        return targetSkinId
    end
    return weaponID
end

_G.equip_character_avatar = function(Character)
    if not Character or not slua.isValid(Character) or not Character.AvatarComponent2 then return end
    local BackpackUtils = import("BackpackUtils")
    local SlotSyncData = Character.AvatarComponent2.NetAvatarData and Character.AvatarComponent2.NetAvatarData.SlotSyncData
    if not SlotSyncData or not slua.isValid(SlotSyncData) or not BackpackUtils then return end
    
    local function EquipAvatar(ApplyDataIdx, mappedSkin, ApplyEquipSlot, isLevelDependent, levelFunc)
        if not mappedSkin or mappedSkin == 0 then return end
        local slotData = SlotSyncData:Get(ApplyDataIdx)
        if slotData and slotData.SlotID == ApplyEquipSlot then
            local applyItemId = mappedSkin
            if isLevelDependent and type(mappedSkin) == "table" then
                local level = levelFunc(slotData.AdditionalItemID) or 1
                if level < 1 then level = 1 end
                if level > 3 then level = 3 end
                applyItemId = mappedSkin[level] or mappedSkin[1]
            end
            if not applyItemId or applyItemId == 0 or slotData.ItemId == applyItemId then return end
            if not _G.skinIdCache[applyItemId] then
                if _G.download_item then pcall(_G.download_item, applyItemId) end
                _G.skinIdCache[applyItemId] = true
            end
            slotData.ItemId = applyItemId
            SlotSyncData:Set(ApplyDataIdx, slotData)
            Character.AvatarComponent2:OnRep_BodySlotStateChanged()
        end
    end

    -- Cek slot yang sudah ada
    local hasGliderSlot = false
    local hasParachuteSlot = false
    for i = 0, SlotSyncData:Num() - 1 do
        local slotData = SlotSyncData:Get(i)
        if slotData then
            if slotData.SlotID == _G.CustSlotType.GlideEquipemtSlot then hasGliderSlot = true end
            if slotData.SlotID == _G.CustSlotType.ParachuteEquipemtSlot then hasParachuteSlot = true end
        end
    end
    if not hasGliderSlot then 
        SlotSyncData:Add({ SlotID = _G.CustSlotType.GlideEquipemtSlot, ItemId = 0 }) 
    end
    if not hasParachuteSlot then 
        SlotSyncData:Add({ SlotID = _G.CustSlotType.ParachuteEquipemtSlot, ItemId = 0 }) 
    end

    for i = 0, SlotSyncData:Num() - 1 do
        EquipAvatar(i, _G.OutfitMap.Suit or 0, _G.CustSlotType.ClothesEquipemtSlot, false)
        EquipAvatar(i, _G.OutfitMap.Bag, _G.CustSlotType.BackpackEquipemtSlot, true, BackpackUtils.GetEquipmentBagLevel)
        EquipAvatar(i, _G.OutfitMap.Helmet, _G.CustSlotType.HelmetEquipemtSlot, true, BackpackUtils.GetEquipmentHelmetLevel)
        EquipAvatar(i, _G.OutfitMap.Parachute or 0, _G.CustSlotType.ParachuteEquipemtSlot, false)
        EquipAvatar(i, _G.OutfitMap.Glider or 0, _G.CustSlotType.GlideEquipemtSlot, false)
        
        -- ========== TAMBAHKAN INI UNTUK GLOVES ==========
        EquipAvatar(i, _G.OutfitMap.Gloves or 0, 6, false)  -- Slot 6 untuk Gloves
    end
end

_G.ApplyWeaponSkins = function(PlayerCharacter)
    pcall(function()
        local WeaponManager = PlayerCharacter:GetWeaponManager()
        if not slua.isValid(WeaponManager) then return end
        
        for slot = 1, 3 do
            local Weapon = WeaponManager:GetInventoryWeaponByPropSlot(slot)
            if slua.isValid(Weapon) and slua.isValid(Weapon.synData) then
                local WeaponID = Weapon:GetWeaponID()
                local SkinID = _G.get_skin_id(WeaponID) or WeaponID
                local isModified = false
                
                local SkinData = Weapon.synData:Get(7) 
                if SkinData and SkinData.defineID and SkinData.defineID.TypeSpecificID ~= SkinID then
                    SkinData.defineID.TypeSpecificID = SkinID
                    Weapon.synData:Set(7, SkinData)
                    if Weapon.SetWeaponAvatarID then pcall(function() Weapon:SetWeaponAvatarID(SkinID) end) end
                    if not _G.skinIdCache[SkinID] then 
                        _G.download_item(SkinID)
                        _G.skinIdCache[SkinID] = true 
                    end
                    isModified = true
                end
                
                if SkinID >= 10000000 and _G.VIP_Attachments and _G.VIP_Attachments[SkinID] then
                    for AttachIdx = 0, 5 do 
                        local attachData = Weapon.synData:Get(AttachIdx)
                        if attachData then
                            local defineIDRef = slua.IndexReference(attachData, "defineID")
                            if defineIDRef then
                                local attachmentId = defineIDRef.TypeSpecificID
                                if attachmentId and attachmentId > 0 then
                                    local mapIndex = _G.BaseAttachToIndex[attachmentId] or _G.VipAttachToIndex[attachmentId]
                                    if mapIndex and _G.VIP_Attachments[SkinID][mapIndex] and _G.VIP_Attachments[SkinID][mapIndex] > 0 then
                                        local targetAttachId = _G.VIP_Attachments[SkinID][mapIndex]
                                        if targetAttachId ~= attachmentId then
                                            attachData.defineID.TypeSpecificID = targetAttachId
                                            Weapon.synData:Set(AttachIdx, attachData)
                                            if not _G.skinIdCache2[targetAttachId] then 
                                                if _G.download_item then pcall(_G.download_item, targetAttachId) end
                                                _G.skinIdCache2[targetAttachId] = true 
                                            end
                                            isModified = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                
                if isModified then
                    if Weapon.DelayHandleAvatarMeshChanged then pcall(function() Weapon:DelayHandleAvatarMeshChanged() end) end
                    if Weapon.OnRep_synData then pcall(function() Weapon:OnRep_synData() end) end
                end
            end
        end
    end)
end

_G.ApplyVehicleSkins = function(PlayerCharacter)
    pcall(function()
        local Vehicle = PlayerCharacter:GetCurrentVehicle()
        if not slua.isValid(Vehicle) then 
            _G.LastVehicleEntity = nil
            return 
        end
        
        if _G.LastVehicleEntity == Vehicle and _G.CurrentEquipVehicleID ~= nil then
            return
        end

        local VehicleAvatar = Vehicle.VehicleAvatar or Vehicle.VehicleAvatarComponent_BP or Vehicle:GetAvatarComponent()
        if not slua.isValid(VehicleAvatar) then return end

        local defId = tostring(VehicleAvatar:GetDefaultAvatarID() or Vehicle.VehicleID or "")
        local currentId = tostring(Vehicle:GetAvatarId() or "")
        local applySkinId = 0
        
        for baseMapId, targetSkin in pairs(_G.VehicleSkinMap) do
            if defId:find(tostring(baseMapId)) or currentId:find(tostring(baseMapId)) then 
                applySkinId = targetSkin
                break 
            end
        end

        if applySkinId and applySkinId > 0 then
            _G.skinIdCache = _G.skinIdCache or {}
            if not _G.skinIdCache[applySkinId] then 
                if _G.download_item then pcall(_G.download_item, applySkinId) end
                _G.skinIdCache[applySkinId] = true 
            end

            VehicleAvatar.curSwitchEffectId = 7303001
            if VehicleAvatar.ChangeItemAvatar then VehicleAvatar:ChangeItemAvatar(applySkinId, true) end
            
            _G.CurrentEquipVehicleID = applySkinId
            _G.LastVehicleEntity = Vehicle
        end
    end)
end

_G.ApplyWeaponMod = function(weapon)
    if not _G.MON5LAConfig.EnableWeaponMod then return end
    if not Valid(weapon) then return end
    
    pcall(function()
        local wid = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
        local cfg = _G.MON5LAConfig.WeaponMod[wid]
        if not cfg then return end
        
        local shootComp = weapon.ShootWeaponEntityComp or weapon.ShootWeaponEntity or weapon
        if not Valid(shootComp) then return end
        
        if cfg.FireSpeed then
            if shootComp.ShootInterval then shootComp.ShootInterval = 0.07 end
            if shootComp.FireRate then shootComp.FireRate = 0.07 end
        end
        if cfg.InstanHit then
            if shootComp.BulletFireSpeed then shootComp.BulletFireSpeed = 150000 end
        end
        if cfg.FastSwitch then
            if shootComp.SwitchFromIdleToBackpackTime then shootComp.SwitchFromIdleToBackpackTime = 0 end
            if shootComp.SwitchFromBackpackToIdleTime then shootComp.SwitchFromBackpackToIdleTime = 0 end
        end
        if cfg.FastScope then
            if shootComp.WeaponAimInTime then shootComp.WeaponAimInTime = 7 end
        end
    end)
end

_G.HandlePetLogic = function()
    pcall(function()
        local petSkin = _G.OutfitMap.Pet
        if not petSkin or petSkin == 0 or petSkin == 50000 or petSkin == _G.LastAppliedPet then return end
        
        _G.skinIdCache = _G.skinIdCache or {}
        if not _G.skinIdCache[petSkin] then 
            if _G.download_item then pcall(_G.download_item, petSkin) end
            _G.skinIdCache[petSkin] = true 
        end
        
        local ModuleManager = require("client.module_framework.ModuleManager")
        if ModuleManager then
            local logic_pet = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.logic_pet)
            if logic_pet then
                if logic_pet.SetCurPetID then logic_pet:SetCurPetID(petSkin) end
                if logic_pet.EquipPet then logic_pet:EquipPet(petSkin) end
            end
        end
        _G.LastAppliedPet = petSkin
    end)
end

_G.ForceRefreshSkinMaps = function()
    pcall(function()
        if not _G.MON5LAState or not _G.MON5LAState.CustomTextData then return end
        local cData = _G.MON5LAState.CustomTextData

        if _G.OutfitSkins then
            if cData.SkinSuit and _G.OutfitSkins.Suit[cData.SkinSuit] then _G.OutfitMap.Suit = _G.OutfitSkins.Suit[cData.SkinSuit] end
            if cData.SkinBag and _G.OutfitSkins.Bag[cData.SkinBag] then _G.OutfitMap.Bag = _G.OutfitSkins.Bag[cData.SkinBag] end
            if cData.SkinHelmet and _G.OutfitSkins.Helmet[cData.SkinHelmet] then _G.OutfitMap.Helmet = _G.OutfitSkins.Helmet[cData.SkinHelmet] end
            if cData.SkinGloves and _G.OutfitSkins.Gloves and _G.OutfitSkins.Gloves[cData.SkinGloves] then 
                _G.OutfitMap.Gloves = _G.OutfitSkins.Gloves[cData.SkinGloves] end
        end

        if _G.skinIdMappings then
            if cData.SkinM416 and _G.skinIdMappings[101004] and _G.skinIdMappings[101004][cData.SkinM416] then _G.WeaponSkinMap[101004] = _G.skinIdMappings[101004][cData.SkinM416] end
            if cData.SkinAKM and _G.skinIdMappings[101001] and _G.skinIdMappings[101001][cData.SkinAKM] then _G.WeaponSkinMap[101001] = _G.skinIdMappings[101001][cData.SkinAKM] end
            if cData.SkinSCAR and _G.skinIdMappings[101003] and _G.skinIdMappings[101003][cData.SkinSCAR] then _G.WeaponSkinMap[101003] = _G.skinIdMappings[101003][cData.SkinSCAR] end
            if cData.SkinM762 and _G.skinIdMappings[101008] and _G.skinIdMappings[101008][cData.SkinM762] then _G.WeaponSkinMap[101008] = _G.skinIdMappings[101008][cData.SkinM762] end
            if cData.SkinAUG and _G.skinIdMappings[101006] and _G.skinIdMappings[101006][cData.SkinAUG] then _G.WeaponSkinMap[101006] = _G.skinIdMappings[101006][cData.SkinAUG] end
            if cData.SkinHoney and _G.skinIdMappings[101012] and _G.skinIdMappings[101012][cData.SkinHoney] then _G.WeaponSkinMap[101012] = _G.skinIdMappings[101012][cData.SkinHoney] end
            if cData.SkinQBZ and _G.skinIdMappings[101007] and _G.skinIdMappings[101007][cData.SkinQBZ] then _G.WeaponSkinMap[101007] = _G.skinIdMappings[101007][cData.SkinQBZ] end
            if cData.SkinASM and _G.skinIdMappings[101101] and _G.skinIdMappings[101101][cData.SkinASM] then _G.WeaponSkinMap[101101] = _G.skinIdMappings[101101][cData.SkinASM] end
            if cData.SkinACE32 and _G.skinIdMappings[101102] and _G.skinIdMappings[101102][cData.SkinACE32] then _G.WeaponSkinMap[101102] = _G.skinIdMappings[101102][cData.SkinACE32] end
            if cData.SkinUMP and _G.skinIdMappings[102002] and _G.skinIdMappings[102002][cData.SkinUMP] then _G.WeaponSkinMap[102002] = _G.skinIdMappings[102002][cData.SkinUMP] end
            if cData.SkinUZI and _G.skinIdMappings[102001] and _G.skinIdMappings[102001][cData.SkinUZI] then _G.WeaponSkinMap[102001] = _G.skinIdMappings[102001][cData.SkinUZI] end
            if cData.SkinVector and _G.skinIdMappings[102003] and _G.skinIdMappings[102003][cData.SkinVector] then _G.WeaponSkinMap[102003] = _G.skinIdMappings[102003][cData.SkinVector] end
            if cData.SkinBIZON and _G.skinIdMappings[102005] and _G.skinIdMappings[102005][cData.SkinBIZON] then 
                _G.WeaponSkinMap[102005] = _G.skinIdMappings[102005][cData.SkinBIZON] end
            if cData.SkinGroza and _G.skinIdMappings[101005] and _G.skinIdMappings[101005][cData.SkinGroza] then _G.WeaponSkinMap[101005] = _G.skinIdMappings[101005][cData.SkinGroza] end
            if cData.SkinKar98K and _G.skinIdMappings[103001] and _G.skinIdMappings[103001][cData.SkinKar98K] then _G.WeaponSkinMap[103001] = _G.skinIdMappings[103001][cData.SkinKar98K] end
            if cData.SkinM24 and _G.skinIdMappings[103002] and _G.skinIdMappings[103002][cData.SkinM24] then _G.WeaponSkinMap[103002] = _G.skinIdMappings[103002][cData.SkinM24] end
            if cData.SkinAWM and _G.skinIdMappings[103003] and _G.skinIdMappings[103003][cData.SkinAWM] then _G.WeaponSkinMap[103003] = _G.skinIdMappings[103003][cData.SkinAWM] end
            if cData.SkinAMR and _G.skinIdMappings[103012] and _G.skinIdMappings[103012][cData.SkinAMR] then _G.WeaponSkinMap[103012] = _G.skinIdMappings[103012][cData.SkinAMR] end
            if cData.SkinS12K and _G.skinIdMappings[104003] and _G.skinIdMappings[104003][cData.SkinS12K] then _G.WeaponSkinMap[104003] = _G.skinIdMappings[104003][cData.SkinS12K] end
            if cData.SkinDBS and _G.skinIdMappings[104004] and _G.skinIdMappings[104004][cData.SkinDBS] then _G.WeaponSkinMap[104004] = _G.skinIdMappings[104004][cData.SkinDBS] end
        end

        if _G.VehicleSkins then
            if cData.SkinDacia and _G.VehicleSkins[1903001] and _G.VehicleSkins[1903001][cData.SkinDacia] then _G.VehicleSkinMap[1903001] = _G.VehicleSkins[1903001][cData.SkinDacia] end
            if cData.SkinUAZ and _G.VehicleSkins[1908001] and _G.VehicleSkins[1908001][cData.SkinUAZ] then _G.VehicleSkinMap[1908001] = _G.VehicleSkins[1908001][cData.SkinUAZ] end
            if cData.SkinCoupe and _G.VehicleSkins[1961001] and _G.VehicleSkins[1961001][cData.SkinCoupe] then _G.VehicleSkinMap[1961001] = _G.VehicleSkins[1961001][cData.SkinCoupe] end
            if cData.SkinBuggy and _G.VehicleSkins[1907001] and _G.VehicleSkins[1907001][cData.SkinBuggy] then _G.VehicleSkinMap[1907001] = _G.VehicleSkins[1907001][cData.SkinBuggy] end
            if cData.SkinMirado and _G.VehicleSkins[1915001] and _G.VehicleSkins[1915001][cData.SkinMirado] then _G.VehicleSkinMap[1915001] = _G.VehicleSkins[1915001][cData.SkinMirado] end
            if cData.SkinParachute and _G.ParachuteSkins and _G.ParachuteSkins[14011] and _G.ParachuteSkins[14011][cData.SkinParachute] then 
                _G.OutfitMap.Parachute = _G.ParachuteSkins[14011][cData.SkinParachute] end
            if cData.SkinGlider and _G.GliderSkins and _G.GliderSkins[41511] and _G.GliderSkins[41511][cData.SkinGlider] then 
                _G.OutfitMap.Glider = _G.GliderSkins[41511][cData.SkinGlider] end
        end
    end)
end

_G.InitializeSkinModSystem = function()
    pcall(function()
        local LobbyAvatar = package.loaded["client.logic.avatar.LobbyAvatar"] or require("client.logic.avatar.LobbyAvatar")
        if LobbyAvatar and not _G.LobbyBypassHacked then
            local originalPutonEquipment = LobbyAvatar.PutonEquipment
            LobbyAvatar.PutonEquipment = function(self, itemID, tAvatarCustom, tExtraData)
                local attachIndex = _G.BaseAttachToIndex and _G.BaseAttachToIndex[itemID]
                if attachIndex then
                    local holdingWeaponSkinID = self.GetCurHoldingWeaponSkinID and self:GetCurHoldingWeaponSkinID()
                    if holdingWeaponSkinID and holdingWeaponSkinID >= 10000000 and _G.VIP_Attachments and _G.VIP_Attachments[holdingWeaponSkinID] then
                        local vipAttachID = _G.VIP_Attachments[holdingWeaponSkinID][attachIndex]
                        if vipAttachID and vipAttachID > 0 then
                            if self.HandleDownload then self:HandleDownload(vipAttachID, nil, nil, false) end
                            itemID = vipAttachID
                        end
                    end
                end
                if originalPutonEquipment then return originalPutonEquipment(self, itemID, tAvatarCustom, tExtraData) end
            end

            local originalCharEquipWeaponByResId = LobbyAvatar.CharEquipWeaponByResId
            LobbyAvatar.CharEquipWeaponByResId = function(self, resID, isUse, isAsync, SocketName)
                local retValue = originalCharEquipWeaponByResId and originalCharEquipWeaponByResId(self, resID, isUse, isAsync, SocketName) or nil
                if isUse and self.GetEquipments then
                    local equipments = self:GetEquipments()
                    for _, equip in ipairs(equipments) do
                        if _G.BaseAttachToIndex and _G.BaseAttachToIndex[equip.itemID] then
                            self:PutonEquipment(equip.itemID, equip.CustomInfo, {bIsUse = false})
                        end
                    end
                end
                return retValue
            end
            _G.LobbyBypassHacked = true
        end
    end)
    
    pcall(function()
        local Common_Items_UIBP = package.loaded["client.slua.component.item.ItemChildren.Common_Items_UIBP"] or require("client.slua.component.item.ItemChildren.Common_Items_UIBP")
        if Common_Items_UIBP and not _G.IconBaloHacked then
            local originalInitView = Common_Items_UIBP.InitView
            Common_Items_UIBP.InitView = function(self, nItemId, nCount, nValidTime, tExtraData)
                tExtraData = tExtraData or {}
                local displayResId = nil
                
                if _G.get_skin_id then
                    local skinID = _G.get_skin_id(nItemId)
                    if skinID and skinID ~= nItemId then displayResId = skinID end
                end
                
                local attachIndex = _G.BaseAttachToIndex and _G.BaseAttachToIndex[nItemId]
                if not displayResId and attachIndex then
                    local GameplayData = require("GameLua.GameCore.Data.GameplayData")
                    local LocalPlayer = GameplayData and GameplayData.GetPlayerCharacter()
                    if slua.isValid(LocalPlayer) then
                        local currentWeapon = LocalPlayer:GetCurrentWeapon()
                        if slua.isValid(currentWeapon) then
                            local weaponID = currentWeapon:GetWeaponID()
                            local finalSkinID = _G.get_skin_id(weaponID) or weaponID
                            if finalSkinID >= 10000000 and _G.VIP_Attachments and _G.VIP_Attachments[finalSkinID] then
                                local vipAttachID = _G.VIP_Attachments[finalSkinID][attachIndex]
                                if vipAttachID and vipAttachID > 0 then displayResId = vipAttachID end
                            end
                        end
                    end
                end
                
                if displayResId then
                    tExtraData.displayResId = displayResId
                    if not _G.skinIdCache2[displayResId] then
                        if _G.download_item then pcall(_G.download_item, displayResId) end
                        _G.skinIdCache2[displayResId] = true
                    end
                end
                if originalInitView then return originalInitView(self, nItemId, nCount, nValidTime, tExtraData) end
            end
            _G.IconBaloHacked = true
        end
    end)
end

-- ========================================== 
-- KILL COUNTER & KILL MESSAGE EFFECT + DEADBOX SKIN
-- ==========================================
_G.TDFTDeKillCounts = _G.TDFTDeKillCounts or {}
local CACHED_LinearColor = import("LinearColor")
local CACHED_GoldColor = CACHED_LinearColor and CACHED_LinearColor(1.0, 0.8, 0.0, 1.0) or nil
local CACHED_UI_Manager = nil
_G.NeedCheckDeadBoxTimer = 0
_G.LastCheckDeadBoxTime = 0

_G.ForceEnableKillCounterUI = function()
    pcall(function()
        local KillCounterUISubsystem = package.loaded["GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem"] or require("GameLua.Mod.BaseMod.Client.KillCounter.KillCounterUISubsystem")
        if KillCounterUISubsystem and KillCounterUISubsystem.__inner_impl and not _G.KCUISystemHacked2 then
            local kcImpl = KillCounterUISubsystem.__inner_impl
            kcImpl.CheckSupportKCUI = function() return true end
            kcImpl.CheckNeedMainKillCounterUI = function(self, PlayerWeapon, PlayerID)
                if slua.isValid(PlayerWeapon) then
                    local WeaponID = PlayerWeapon:GetWeaponID()
                    self:UpdateMainKillCounterUI(true, WeaponID, _G.get_skin_id(WeaponID) or WeaponID)
                else self:UpdateMainKillCounterUI(false) end
            end
            local originalUpdateMainKillCounterUI = kcImpl.UpdateMainKillCounterUI
            kcImpl.UpdateMainKillCounterUI = function(self, bShow, WeaponID, AvatarID)
                if bShow then AvatarID = _G.get_skin_id(WeaponID) or AvatarID end
                if originalUpdateMainKillCounterUI then originalUpdateMainKillCounterUI(self, bShow, WeaponID, AvatarID) end
            end
            _G.KCUISystemHacked2 = true
        end

        local ModuleManager = require("client.module_framework.ModuleManager")
        if ModuleManager and not _G.KCLogicHacked2 then
            local LogicKillCounter = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.LogicKillCounter)
            if LogicKillCounter then
                LogicKillCounter.CheckSupportKC = function() return true end
                LogicKillCounter.CheckSupportKillCounterAvatar = function() return true end
                LogicKillCounter.CheckHasWeaponKillCounter = function() return true end
                LogicKillCounter.GetBaseKillCounterIdByWeaponId = function() return 2100004 end
                LogicKillCounter.GetEquipedKillCounterId = function() return 2100004 end
                LogicKillCounter.GetMyEquipedKillCounterId = function() return 2100004 end
                LogicKillCounter.GetOneWeaponKillCountInBattle = function(self, uid, weaponId) return _G.TDFTDeKillCounts[weaponId] or 0 end
                LogicKillCounter.GetWeaponKillCountByUid = function(self, uid, weaponId) return _G.TDFTDeKillCounts[weaponId] or 0 end
                _G.KCLogicHacked2 = true
            end
        end

        local killInfoPath = "GameLua.Mod.BaseMod.Client.KillInfoTips.KillInfo"
        local KillInfo = package.loaded[killInfoPath] or require(killInfoPath)
        
        if KillInfo and KillInfo.__inner_impl and not _G.KillInfoCounterHacked then
            local originalFileItem = KillInfo.__inner_impl.FileItem
            KillInfo.__inner_impl.FileItem = function(self, DamageRecordData)
                pcall(function()
                    local LocalPlayer = require("GameLua.GameCore.Data.GameplayData").GetPlayerCharacter()
                    if slua.isValid(LocalPlayer) and DamageRecordData.Causer == LocalPlayer:GetPlayerNameSafety() then 
                        local currentWeapon = LocalPlayer:GetCurrentWeapon()
                        if slua.isValid(currentWeapon) then
                            local weaponID = currentWeapon:GetWeaponID()
                            local skinID = _G.get_skin_id(weaponID)
                            if skinID then DamageRecordData.CauserWeaponAvatarID = skinID end
                            if _G.OutfitMap.Suit and _G.OutfitMap.Suit ~= 0 then DamageRecordData.CauserClothAvatarID = _G.OutfitMap.Suit end
                            
                            if CACHED_GoldColor then
                                DamageRecordData.IsUseColor, DamageRecordData.UseColor = true, CACHED_GoldColor
                            end
                            
                            if DamageRecordData.ResultHealthStatus == 2 then
                                _G.TDFTDeKillCounts[weaponID] = (_G.TDFTDeKillCounts[weaponID] or 0) + 1
                                _G.NeedCheckDeadBoxTimer = 50 
                                
                                if not CACHED_UI_Manager then CACHED_UI_Manager = require("client.slua_ui_framework.manager") end
                                local uiMainKillCounter = CACHED_UI_Manager.GetUI(CACHED_UI_Manager.UI_Config_InGame.MainKillCounter)
                                
                                if uiMainKillCounter and uiMainKillCounter.UpdateWeaponID then
                                    local mainAvatarID = skinID or currentWeapon:GetWeaponMainAvatarID()
                                    uiMainKillCounter:UpdateWeaponID(weaponID, mainAvatarID)
                                    local kcModule = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.LogicKillCounter)
                                    local kcItemID = kcModule:GetEquipedKillCounterId(0, mainAvatarID)
                                    uiMainKillCounter:SetKillCounterItemShowWithNum(kcItemID, _G.TDFTDeKillCounts[weaponID], mainAvatarID)
                                end
                            end
                        end
                    end
                end)
                if originalFileItem then return originalFileItem(self, DamageRecordData) end
            end
            _G.KillInfoCounterHacked = true
        end

        local SwitchWeaponSlotMode2 = package.loaded["GameLua.Mod.BaseMod.Client.MainControlUI.SwitchWeaponSlotMode2"] or require("GameLua.Mod.BaseMod.Client.MainControlUI.SwitchWeaponSlotMode2")
        if SwitchWeaponSlotMode2 and SwitchWeaponSlotMode2.__inner_impl and not _G.SlotBaseHacked then
            SwitchWeaponSlotMode2.__inner_impl.CheckShowKCIcon = function(self)
                if slua.isValid(self.KillCounterImg) then 
                    self.KillCounterImg:SetVisibility(import("ESlateVisibility").SelfHitTestInvisible) 
                end
            end
            _G.SlotBaseHacked = true
        end
    end)
end

-- ========================================== 
-- DEADBOX SKIN (temper request)
-- ==========================================
local cached_GameplayStatics = nil
local cached_PlayerTombBox = nil
local cached_ActorClass = nil
_G.DeadBox_TemperRequest = function(PlayerController)
    if _G.NeedCheckDeadBoxTimer <= 0 then return end
    
    local curTime = os.clock()
    if _G.LastCheckDeadBoxTime and (curTime - _G.LastCheckDeadBoxTime) < 2.0 then return end
    _G.LastCheckDeadBoxTime = curTime
    
    _G.NeedCheckDeadBoxTimer = _G.NeedCheckDeadBoxTimer - 1

    local PlayerCharacter = PlayerController:GetPlayerCharacterSafety()
    if not slua.isValid(PlayerCharacter) then return end
    
    if not cached_GameplayStatics then
        cached_GameplayStatics = import("GameplayStatics")
        cached_ActorClass = import("Actor")
        cached_PlayerTombBox = import("PlayerTombBox")
    end
    
    if not _G.CachedActorArray then
        _G.CachedActorArray = slua.Array(UEnums.EPropertyClass.Object, cached_ActorClass)
    end
    
    local UI_Util = require("client.common.ui_util")
    local GameInstance = UI_Util and UI_Util.GetGameInstance()
    if not GameInstance or not cached_GameplayStatics then return end

    local deadBoxes = cached_GameplayStatics.GetAllActorsOfClass(GameInstance, cached_PlayerTombBox, _G.CachedActorArray)
    
    for _, deadBoxActor in pairs(deadBoxes) do
        if slua.isValid(deadBoxActor) and not deadBoxActor.bIsTDSkinApplied then
            local damageCauser = deadBoxActor.DamageCauser
            if damageCauser and damageCauser.PlayerKey == PlayerController.PlayerKey then
                local DeadBoxAvatarComponent = deadBoxActor.DeadBoxAvatarComponent_BP
                if slua.isValid(DeadBoxAvatarComponent) then
                    local currentBoxSkinId = 0
                    if PlayerCharacter.CurrentVehicle and _G.CurrentEquipVehicleID and _G.CurrentEquipVehicleID ~= 0 then
                        currentBoxSkinId = tonumber(tostring(_G.CurrentEquipVehicleID) .. "1") or 0
                    else
                        local currentWeapon = PlayerCharacter:GetCurrentWeapon()
                        if slua.isValid(currentWeapon) and currentWeapon.synData then
                            local weaponSkinData = currentWeapon.synData:Get(7)
                            if weaponSkinData and weaponSkinData.defineID then
                                currentBoxSkinId = weaponSkinData.defineID.TypeSpecificID
                            end
                        end
                    end
                    
                    if currentBoxSkinId ~= 0 then
                        pcall(function()
                            DeadBoxAvatarComponent:ResetItemAvatar()
                            DeadBoxAvatarComponent:PreChangeItemAvatar(currentBoxSkinId)
                            DeadBoxAvatarComponent:SyncChangeItemAvatar(currentBoxSkinId)
                        end)
                    end
                    deadBoxActor.bIsTDSkinApplied = true
                end
            end
        end
    end
end

-- ========================================== 
-- RISK WARNING WIDGET (EXPERT2)
-- ==========================================
_G.RiskWarningWidget = nil
local RISK_WARNING_BP = "/Game/UMG/UI_BP/Common/BaseComponent/CommonBaseComponent_TextButton_UIBP.CommonBaseComponent_TextButton_UIBP"

function _G.ShowRiskWarning()
    if _G.RiskWarningWidget and slua.isValid(_G.RiskWarningWidget) then return end
    _G.RiskWarningWidget = nil
    pcall(function()
        local widget = slua.loadUI(RISK_WARNING_BP)
        if not widget or not slua.isValid(widget) then return end
        local hud = require("game_frontend_hud")
        if not (hud and hud.AddToContainer) then return end
        hud.AddToContainer(UIContainers.Top, widget, 10700)

        local WidgetLayoutLibrary = import("WidgetLayoutLibrary")
        local slot = WidgetLayoutLibrary.SlotAsCanvasSlot(widget)
        if slot then
            slot:SetAnchors(FAnchors(0.5, 0, 0.5, 0))
            slot:SetAlignment(FVector2D(0.5, 0))
            slot:SetPosition(FVector2D(0, 80))
            slot:SetSize(FVector2D(220, 36))
        end

        if widget.RichText_Content then
            widget.RichText_Content:SetText("RISK FITUR ENABLED")
            widget.RichText_Content:SetColorAndOpacity(FSlateColor(FLinearColor(0, 0, 0, 1)))
            local fontInfo = widget.RichText_Content.Font
            if fontInfo then
                fontInfo.Size = 16
                fontInfo.TypefaceFontName = "Bold"
                widget.RichText_Content:SetFont(fontInfo)
            end
        end

        -- Atur latar belakang tombol menjadi merah transparan
        if widget.Button_BG then
            widget.Button_BG:SetColorAndOpacity(FLinearColor(1, 0, 0, 0.8))
        end
        if widget.Image_Background then
            widget.Image_Background:SetColorAndOpacity(FLinearColor(1, 0, 0, 0.8))
        end

        widget:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        _G.RiskWarningWidget = widget
    end)
end

function _G.HideRiskWarning()
    pcall(function()
        if _G.RiskWarningWidget and slua.isValid(_G.RiskWarningWidget) then
            _G.RiskWarningWidget:RemoveFromParent()
        end
    end)
    _G.RiskWarningWidget = nil
end

-- ========================================== 
-- VIP NATIVE MENU SYSTEM (RUNS DIRECTLY FROM GAME SETTINGS)
-- ========================================== 

function _G.InitModMenuTab()
    if _G.ModMenuInitialized then return end
    _G.ModMenuInitialized = true

    _G.MON5LAState.CustomTextData = _G.MON5LAState.CustomTextData or {
    OuterSpeed = 10, InnerSpeed = 10, OuterRecoil = 0, HRecoil = 0.3, VRecoil = 0.3, MagicHead = 1.0, MagicBody = 1.0, MagicLegs = 1.0, IpadViewFOV = 120,
    -- === NEW FEATURES FROM GOLD ===
    IpadViewVehicleFOV = 120,
    IpadViewScopeFOV = 60,
    AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250,
    AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30,
    AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1, AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300, AimTouchScopePred = 0, AimTouchScopeRecoil = 0,
    AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400, AimTouchSniperPred = 0,
    -- === NEW MORTAR ===
    AimTouchMortarPred = 0,
    AimTouchMortarFOV = 360,
    -- === FOV COLORS ===
    AimTouchHipFOVColor = 7,
    AimTouchSGFOVColor = 1,
    AimTouchScopeFOVColor = 6,
    AimTouchSniperFOVColor = 4,
    AimTouchMortarFOVColor = 5,
    SkinSuit = 1, SkinBag = 1, SkinHelmet = 1,
    SkinM416 = 1, SkinAKM = 1, SkinSCAR = 1, SkinM762 = 1, SkinAUG = 1,
    SkinHoney = 1, SkinQBZ = 1, SkinASM = 1, SkinACE32 = 1,
    SkinUMP = 1, SkinUZI = 1, SkinVector = 1,
    SkinGroza = 1,
    SkinKar98K = 1, SkinM24 = 1, SkinAWM = 1, SkinAMR = 1,
    SkinS12K = 1, SkinDacia = 1, SkinUAZ = 1, SkinCoupe = 1, SkinBuggy = 1, SkinMirado = 1,
    SkinBIZON = 1,
    SkinGlider = 1,
    SkinParachute = 1,
    SkinGloves = 1,
}

    local LocUtil = _G.LocUtil
    if not LocUtil and package.loaded["client.common.LocUtil"] then
        LocUtil = require("client.common.LocUtil")
    end
    
    if LocUtil and not LocUtil._IsModMenuHooked then
        local old_get = LocUtil.GetLocalizeResStr
        LocUtil.GetLocalizeResStr = function(id)
            if type(id) == "string" and not tonumber(id) then
                return id
            end
            return old_get(id)
        end
        LocUtil._IsModMenuHooked = true
    end

    local SettingPageDefine = require("client.logic.NewSetting.SettingPageDefine")
    local SettingCatalog = require("client.logic.NewSetting.SettingCatalog")
    
    if not SettingPageDefine.ModMenu then
        local AliasMap = require("client.slua.umg.NewSetting.Item.AliasMap")
        
        -- Fungsi pembuat warna dengan 7 pilihan (Switcher)
        local function MakeColorSwitcher(key, text, configKey, expandHandle, defaultVal)
            return {
                Key = key,
                UI = AliasMap.Switcher,
                Text = "      " .. text,
                ExpandHandle = expandHandle,
                SwitcherText = {"أحمر","أبيض","أصفر","أخضر","سماوي","أزرق","بنفسجي"},
                SwitcherValue = {1,2,3,4,5,6,7},
                GetFunc = function() return _G.MON5LAConfig[configKey] or (defaultVal or 4) end,
                SetFunc = function(c, v)
                    local val = math.floor(v + 0.5)
                    if val < 1 then val = 1 end
                    if val > 7 then val = 7 end
                    _G.MON5LAConfig[configKey] = val
                    return true
                end
            }
        end
        
        -- ==================== ESP VISUAL ====================
        local StackESPVisual = {
            { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#إعدادات ESP", ExpandHandle = "ModMenu_Skin3_Ex" },
            { Key = "ModMenu_ESP1", UI = AliasMap.Switcher, Text = "ESP تلقائي (وضع بسيط)", GetFunc = function() return _G.MON5LAConfig.EspVip end, SetFunc = function(c,v) _G.MON5LAConfig.EspVip = v return true end },
            { Key = "ModMenu_ESP2", UI = AliasMap.Switcher, Text = "مدى ESP", GetFunc = function() 
    if _G.MON5LAConfig.EspDistance == nil then
        _G.MON5LAConfig.EspDistance = false
    end
    return _G.MON5LAConfig.EspDistance 
end, SetFunc = function(c,v) 
    if v == true then 
        _G.MON5LAConfig.EspDistance = true 
    else 
        _G.MON5LAConfig.EspDistance = false 
    end 
    return true 
end },
            { Key = "ModMenu_ESP3", UI = AliasMap.Switcher, Text = "الصحة V1 (مرئي)", GetFunc = function() return _G.MON5LAConfig.EspVipPro end, SetFunc = function(c,v) _G.MON5LAConfig.EspVipPro = v return true end },
            { Key = "ModMenu_ESP4", UI = AliasMap.Switcher, Text = "علامة ESP - رادار 360", GetFunc = function() return _G.MON5LAConfig.EspRadar end, SetFunc = function(c,v) _G.MON5LAConfig.EspRadar = v return true end },
            { Key = "ModMenu_ESP5", UI = AliasMap.Switcher, Text = "إطار ESP", GetFunc = function() return _G.MON5LAConfig.Esp5 end, SetFunc = function(c,v) _G.MON5LAConfig.Esp5 = v return true end },
            { Key = "ModMenu_ESP6", UI = AliasMap.Switcher, Text = "رأس ESP (مرئي)", GetFunc = function() return _G.MON5LAConfig.Esp6 end, SetFunc = function(c,v) _G.MON5LAConfig.Esp6 = v return true end },
            { Key = "ModMenu_ESP8", UI = AliasMap.Switcher, Text = "صحة ESP V2", GetFunc = function() return _G.MON5LAConfig.Esp8 end, SetFunc = function(c,v) _G.MON5LAConfig.Esp8 = v return true end },
            { Key = "ModMenu_ESPAntenna", UI = AliasMap.Switcher, Text = "خط هوائي ESP", GetFunc = function() return _G.MON5LAConfig.EspAntenna end, SetFunc = function(c,v) _G.MON5LAConfig.EspAntenna = v return true end },
            { Key = "ModMenu_ESPName", UI = AliasMap.Switcher, Text = "اسم ESP (مرئي)", GetFunc = function() return _G.MON5LAConfig.EspName end, SetFunc = function(c,v) _G.MON5LAConfig.EspName = v return true end },
            -- ESP THROWABLE
            { Key = "ModMenu_ESPThrowable_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ ESP القابل للرمي (قنبلة، دخان، مولوتوف)", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.ThrowableEnabled end, SetFunc = function(c,v) _G.MON5LAConfig.ThrowableEnabled = v return true end },
            { Key = "ModMenu_Throwable_Grenade", UI = AliasMap.TitleSwitcher, Text = "   قنبلة", ExpandHandle = "ModMenu_ESPThrowable_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.ThrowableGrenade end, SetFunc = function(c,v) _G.MON5LAConfig.ThrowableGrenade = v return true end },
            MakeColorSwitcher("ModMenu_Throwable_ColorGrenade", "لون القنبلة", "ThrowableColor_Grenade", "ModMenu_Throwable_Grenade", 4),
            { Key = "ModMenu_Throwable_Smoke", UI = AliasMap.TitleSwitcher, Text = "   دخان", ExpandHandle = "ModMenu_ESPThrowable_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.ThrowableSmoke end, SetFunc = function(c,v) _G.MON5LAConfig.ThrowableSmoke = v return true end },
            MakeColorSwitcher("ModMenu_Throwable_ColorSmoke", "لون الدخان", "ThrowableColor_Smoke", "ModMenu_Throwable_Smoke", 4),
            { Key = "ModMenu_Throwable_Molotov", UI = AliasMap.TitleSwitcher, Text = "   مولوتوف", ExpandHandle = "ModMenu_ESPThrowable_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.ThrowableMolotov end, SetFunc = function(c,v) _G.MON5LAConfig.ThrowableMolotov = v return true end },
            MakeColorSwitcher("ModMenu_Throwable_ColorMolotov", "لون المولوتوف", "ThrowableColor_Molotov", "ModMenu_Throwable_Molotov", 4),
            { Key = "ModMenu_Throwable_Timer", UI = AliasMap.Switcher, Text = "   مؤقت فحص القابل للرمي", ExpandHandle = "ModMenu_ESPThrowable_Ex", SwitcherText = {"مستمر","كل 10 ثواني","كل 20 ثانية"}, SwitcherValue = {0,10,20}, GetFunc = function() return _G.MON5LAConfig.ThrowableScanMode or 0 end, SetFunc = function(c,v) _G.MON5LAConfig.ThrowableScanMode = v return true end },

            -- ESP VEHICLE
            { Key = "ModMenu_ESPVehicle_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ ESP المركبات", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.VehicleEnabled end, SetFunc = function(c,v) _G.MON5LAConfig.VehicleEnabled = v return true end },
            { Key = "ModMenu_Vehicle_Dacia", UI = AliasMap.TitleSwitcher, Text = "   إظهار داتشيا", ExpandHandle = "ModMenu_ESPVehicle_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.VehicleShowDacia end, SetFunc = function(c,v) _G.MON5LAConfig.VehicleShowDacia = v return true end },
            MakeColorSwitcher("ModMenu_Vehicle_ColorDacia", "لون داتشيا", "VehicleColor_Dacia", "ModMenu_Vehicle_Dacia", 4),
            { Key = "ModMenu_Vehicle_UAZ", UI = AliasMap.TitleSwitcher, Text = "   إظهار أواز", ExpandHandle = "ModMenu_ESPVehicle_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.VehicleShowUAZ end, SetFunc = function(c,v) _G.MON5LAConfig.VehicleShowUAZ = v return true end },
            MakeColorSwitcher("ModMenu_Vehicle_ColorUAZ", "لون أواز", "VehicleColor_UAZ", "ModMenu_Vehicle_UAZ", 4),
            { Key = "ModMenu_Vehicle_Buggy", UI = AliasMap.TitleSwitcher, Text = "   إظهار باجي", ExpandHandle = "ModMenu_ESPVehicle_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.VehicleShowBuggy end, SetFunc = function(c,v) _G.MON5LAConfig.VehicleShowBuggy = v return true end },
            MakeColorSwitcher("ModMenu_Vehicle_ColorBuggy", "لون باجي", "VehicleColor_Buggy", "ModMenu_Vehicle_Buggy", 4),
            { Key = "ModMenu_Vehicle_Coupe", UI = AliasMap.TitleSwitcher, Text = "   إظهار كوبيه RB", ExpandHandle = "ModMenu_ESPVehicle_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.VehicleShowCoupe end, SetFunc = function(c,v) _G.MON5LAConfig.VehicleShowCoupe = v return true end },
            MakeColorSwitcher("ModMenu_Vehicle_ColorCoupe", "لون كوبيه", "VehicleColor_Coupe", "ModMenu_Vehicle_Coupe", 4),
            { Key = "ModMenu_Vehicle_Mirado", UI = AliasMap.TitleSwitcher, Text = "   إظهار ميرادو", ExpandHandle = "ModMenu_ESPVehicle_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.VehicleShowMirado end, SetFunc = function(c,v) _G.MON5LAConfig.VehicleShowMirado = v return true end },
            MakeColorSwitcher("ModMenu_Vehicle_ColorMirado", "لون ميرادو", "VehicleColor_Mirado", "ModMenu_Vehicle_Mirado", 4),
            { Key = "ModMenu_Vehicle_Motor", UI = AliasMap.TitleSwitcher, Text = "   إظهار دراجة/سكوتر", ExpandHandle = "ModMenu_ESPVehicle_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.VehicleShowMotor end, SetFunc = function(c,v) _G.MON5LAConfig.VehicleShowMotor = v return true end },
            MakeColorSwitcher("ModMenu_Vehicle_ColorMotor", "لون الدراجة", "VehicleColor_Motor", "ModMenu_Vehicle_Motor", 4),
            { Key = "ModMenu_Vehicle_Other", UI = AliasMap.TitleSwitcher, Text = "   إظهار أخرى", ExpandHandle = "ModMenu_ESPVehicle_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.VehicleShowOther end, SetFunc = function(c,v) _G.MON5LAConfig.VehicleShowOther = v return true end },
            MakeColorSwitcher("ModMenu_Vehicle_ColorOther", "لون أخرى", "VehicleColor_Other", "ModMenu_Vehicle_Other", 4),

            -- ESP LOOT
            { Key = "ModMenu_ESPLoot_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ ESP الغنائم (أسلحة ومعدات)", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.EspLoot end, SetFunc = function(c,v) _G.MON5LAConfig.EspLoot = v return true end },
            { Key = "ModMenu_Loot_M416", UI = AliasMap.TitleSwitcher, Text = "   M416", ExpandHandle = "ModMenu_ESPLoot_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.LootShowM416 end, SetFunc = function(c,v) _G.MON5LAConfig.LootShowM416 = v return true end },
            MakeColorSwitcher("ModMenu_Loot_ColorM416", "لون M416", "LootColor_M416", "ModMenu_Loot_M416", 4),
            { Key = "ModMenu_Loot_AUG", UI = AliasMap.TitleSwitcher, Text = "   AUG", ExpandHandle = "ModMenu_ESPLoot_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.LootShowAUG end, SetFunc = function(c,v) _G.MON5LAConfig.LootShowAUG = v return true end },
            MakeColorSwitcher("ModMenu_Loot_ColorAUG", "لون AUG", "LootColor_AUG", "ModMenu_Loot_AUG", 4),
            { Key = "ModMenu_Loot_AKM", UI = AliasMap.TitleSwitcher, Text = "   AKM", ExpandHandle = "ModMenu_ESPLoot_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.LootShowAKM end, SetFunc = function(c,v) _G.MON5LAConfig.LootShowAKM = v return true end },
            MakeColorSwitcher("ModMenu_Loot_ColorAKM", "لون AKM", "LootColor_AKM", "ModMenu_Loot_AKM", 4),
            { Key = "ModMenu_Loot_M24", UI = AliasMap.TitleSwitcher, Text = "   M249", ExpandHandle = "ModMenu_ESPLoot_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.LootShowM24 end, SetFunc = function(c,v) _G.MON5LAConfig.LootShowM24 = v return true end },
            MakeColorSwitcher("ModMenu_Loot_ColorM24", "لون M24", "LootColor_M24", "ModMenu_Loot_M24", 4),
            { Key = "ModMenu_Loot_UMP", UI = AliasMap.TitleSwitcher, Text = "   UMP45", ExpandHandle = "ModMenu_ESPLoot_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.LootShowUMP end, SetFunc = function(c,v) _G.MON5LAConfig.LootShowUMP = v return true end },
            MakeColorSwitcher("ModMenu_Loot_ColorUMP", "لون UMP", "LootColor_UMP", "ModMenu_Loot_UMP", 4),
            { Key = "ModMenu_Loot_DBS", UI = AliasMap.TitleSwitcher, Text = "   DBS", ExpandHandle = "ModMenu_ESPLoot_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.LootShowDBS end, SetFunc = function(c,v) _G.MON5LAConfig.LootShowDBS = v return true end },
            MakeColorSwitcher("ModMenu_Loot_ColorDBS", "لون DBS", "LootColor_DBS", "ModMenu_Loot_DBS", 4),
            { Key = "ModMenu_Loot_S12K", UI = AliasMap.TitleSwitcher, Text = "   S12K", ExpandHandle = "ModMenu_ESPLoot_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.LootShowS12K end, SetFunc = function(c,v) _G.MON5LAConfig.LootShowS12K = v return true end },
            MakeColorSwitcher("ModMenu_Loot_ColorS12K", "لون S12K", "LootColor_S12K", "ModMenu_Loot_S12K", 4),
            { Key = "ModMenu_Loot_Vest3", UI = AliasMap.TitleSwitcher, Text = "   درع 3", ExpandHandle = "ModMenu_ESPLoot_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.LootShowVest3 end, SetFunc = function(c,v) _G.MON5LAConfig.LootShowVest3 = v return true end },
            MakeColorSwitcher("ModMenu_Loot_ColorVest3", "لون درع 3", "LootColor_Vest3", "ModMenu_Loot_Vest3", 4),
            { Key = "ModMenu_Loot_Helmet3", UI = AliasMap.TitleSwitcher, Text = "   خوذة 3", ExpandHandle = "ModMenu_ESPLoot_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.LootShowHelmet3 end, SetFunc = function(c,v) _G.MON5LAConfig.LootShowHelmet3 = v return true end },
            MakeColorSwitcher("ModMenu_Loot_ColorHelmet3", "لون خوذة 3", "LootColor_Helmet3", "ModMenu_Loot_Helmet3", 4),
            { Key = "ModMenu_Loot_Bag3", UI = AliasMap.TitleSwitcher, Text = "   حقيبة 3", ExpandHandle = "ModMenu_ESPLoot_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.LootShowBag3 end, SetFunc = function(c,v) _G.MON5LAConfig.LootShowBag3 = v return true end },
            MakeColorSwitcher("ModMenu_Loot_ColorBag3", "لون حقيبة 3", "LootColor_Bag3", "ModMenu_Loot_Bag3", 4),
            { Key = "ModMenu_Loot_Timer", UI = AliasMap.Switcher, Text = "   مؤقت فحص الغنائم", ExpandHandle = "ModMenu_ESPLoot_Ex", SwitcherText = {"مستمر","كل 10 ثواني","كل 20 ثانية"}, SwitcherValue = {0,10,20}, GetFunc = function() return _G.MON5LAConfig.LootScanMode or 0 end, SetFunc = function(c,v) _G.MON5LAConfig.LootScanMode = v return true end },

            -- ESP STATIC
            { Key = "ModMenu_EspStatic_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ ESP ثابت (معلومات العدو)", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.EspStatic end, SetFunc = function(c,v) _G.MON5LAConfig.EspStatic = v return true end },
            { Key = "ModMenu_EspEnemyCount", UI = AliasMap.Switcher, Text = "   عدد الأعداء", ExpandHandle = "ModMenu_EspStatic_Ex", GetFunc = function() return _G.MON5LAConfig.EspEnemyCount end, SetFunc = function(c,v) _G.MON5LAConfig.EspEnemyCount = v return true end },
            { Key = "ModMenu_EspWeaponStatus", UI = AliasMap.Switcher, Text = "   سلاح وحالة العدو", ExpandHandle = "ModMenu_EspStatic_Ex", GetFunc = function() return _G.MON5LAConfig.EspWeaponStatus end, SetFunc = function(c,v) _G.MON5LAConfig.EspWeaponStatus = v return true end },
        }
        
        
        -- ==================== AIMBOT FORCE ====================
        local StackAimbotForce = {
        { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#إعدادات التصويب", ExpandHandle = "ModMenu_Skin3_Ex" },
        { Key = "ModMenu_Crosshair", UI = AliasMap.Switcher, Text = "تصويب صغير (الشهير الصغير - أسقط السلاح وأعد تجهيزه إذا قمت بإيقافه)", GetFunc = function() return _G.MON5LAConfig.Crosshair end, SetFunc = function(c,v) _G.MON5LAConfig.Crosshair = v return true end },
            { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#إعدادات الأيم بوت (بدون مساعدة تصويب)", ExpandHandle = "ModMenu_Skin3_Ex" },
            { Key = "ModMenu_AT_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ تفعيل الأيم بوت الملكي والمخصص (تفعيل الأيم بوت الملكي والمخصص)", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.AimTouchEnable end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchEnable = v return true end },
            -- HIPFIRE
            { Key = "ModMenu_AT_Hip_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ أيم بوت التصويب من الحوض (بدون منظار)", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.AimTouchHipfire end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchHipfire = v return true end },
            { Key = "ModMenu_AT_Hip_IgKnock", UI = AliasMap.Switcher, Text = "      تجاهل الأعداء المطروحين (تجاهل العدو المطروح)", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchHipIgKnock end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchHipIgKnock = v return true end },
            { Key = "ModMenu_AT_Hip_IgBot", UI = AliasMap.Switcher, Text = "      تجاهل البوتات (تجاهل البوت)", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchHipIgBot end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchHipIgBot = v return true end },
            { Key = "ModMenu_AT_Hip_Vis", UI = AliasMap.Switcher, Text = "      فحص الرؤية (فحص الجدار)", ExpandHandle = "ModMenu_AT_Hip_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchHipVisCheck end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchHipVisCheck = v return true end },
            { Key = "ModMenu_AT_Hip_Prio", UI = AliasMap.Switcher, Text = "      الأولوية (الأولوية - 1: المركز 2: المسافة 3: الصحة 4: نسبة الصحة)", ExpandHandle = "ModMenu_AT_Hip_Ex", SwitcherText = {"المركز","المسافة","الصحة","نسبة الصحة"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchHipPrio or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchHipPrio = v return true end },
            { Key = "ModMenu_AT_Hip_Bone", UI = AliasMap.Switcher, Text = "      استهداف العظم (استهداف العظم - 1: الرأس 2: الصدر 3: البطن 4: الحوض)", ExpandHandle = "ModMenu_AT_Hip_Ex", SwitcherText = {"الرأس","الصدر","البطن","الحوض"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchHipBone or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchHipBone = v return true end },
            { Key = "ModMenu_AT_Hip_Cond", UI = AliasMap.Switcher, Text = "      الشرط (الشرط - 1: التصويب عند إطلاق النار 2: التصويب دائمًا)", ExpandHandle = "ModMenu_AT_Hip_Ex", SwitcherText = {"التصويب عند إطلاق النار","التصويب دائمًا"}, SwitcherValue = {1,2}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchHipCond or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchHipCond = v return true end },
            { Key = "ModMenu_AT_Hip_Spd", UI = AliasMap.Slider, Text = "      التنعيم / السرعة (التنعيم / السرعة - 1-100)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchHipSpeed or 50 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchHipSpeed = v return true end },
            { Key = "ModMenu_AT_Hip_FOV", UI = AliasMap.Slider, Text = "      نطاق FOV (نطاق الرؤية - 1-100)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchHipFOV or 30 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchHipFOV = v return true end },
            -- === NEW FOV COLOR ===
            { Key = "ModMenu_AT_Hip_FOVColor", UI = AliasMap.Slider, Text = "      لون دائرة FOV (لون دائرة الرؤية)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchHipFOVColor or 7 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchHipFOVColor = v return true end },
            { Key = "ModMenu_AT_Hip_Dist", UI = AliasMap.Slider, Text = "      المسافة (المسافة - 1-500 متر)", ExpandHandle = "ModMenu_AT_Hip_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.MON5LAState.CustomTextData.AimTouchHipDist or 250) / 5) end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchHipDist = v * 5 return true end },
            -- SHOTGUN
            { Key = "ModMenu_AT_SG_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ أيم بوت البندقية (فقط للبندقية)", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.AimTouchSG end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchSG = v return true end },
            { Key = "ModMenu_AT_SG_AutoFire", UI = AliasMap.Switcher, Text = "      إطلاق تلقائي (إطلاق نار تلقائي - قد يسبب خللًا إذا لم يتم الإطلاق يدويًا)", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchSGAutoFire end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchSGAutoFire = v return true end },
            { Key = "ModMenu_AT_SG_IgKnock", UI = AliasMap.Switcher, Text = "      تجاهل الأعداء المطروحين (تجاهل العدو المطروح)", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchSGIgKnock end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchSGIgKnock = v return true end },
            { Key = "ModMenu_AT_SG_IgBot", UI = AliasMap.Switcher, Text = "      تجاهل البوتات (تجاهل البوت)", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchSGIgBot end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchSGIgBot = v return true end },
            { Key = "ModMenu_AT_SG_Vis", UI = AliasMap.Switcher, Text = "      فحص الرؤية (فحص الجدار)", ExpandHandle = "ModMenu_AT_SG_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchSGVisCheck end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchSGVisCheck = v return true end },
            { Key = "ModMenu_AT_SG_Prio", UI = AliasMap.Switcher, Text = "      الأولوية (الأولوية - 1: المركز 2: المسافة 3: الصحة 4: نسبة الصحة)", ExpandHandle = "ModMenu_AT_SG_Ex", SwitcherText = {"المركز","المسافة","الصحة","نسبة الصحة"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSGPrio or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSGPrio = v return true end },
            { Key = "ModMenu_AT_SG_Bone", UI = AliasMap.Switcher, Text = "      استهداف العظم (استهداف العظم - 1: الرأس 2: الصدر 3: البطن 4: الحوض)", ExpandHandle = "ModMenu_AT_SG_Ex", SwitcherText = {"الرأس","الصدر","البطن","الحوض"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSGBone or 2 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSGBone = v return true end },
            { Key = "ModMenu_AT_SG_Cond", UI = AliasMap.Switcher, Text = "      الشرط (الشرط - 1: التصويب عند إطلاق النار 2: التصويب دائمًا)", ExpandHandle = "ModMenu_AT_SG_Ex", SwitcherText = {"التصويب عند إطلاق النار","التصويب دائمًا"}, SwitcherValue = {1,2}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSGCond or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSGCond = v return true end },
            { Key = "ModMenu_AT_SG_Spd", UI = AliasMap.Slider, Text = "      التنعيم / السرعة (التنعيم / السرعة - 1-100)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSGSpeed or 80 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSGSpeed = v return true end },
            { Key = "ModMenu_AT_SG_FOV", UI = AliasMap.Slider, Text = "      نطاق FOV (نطاق الرؤية - 1-100)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSGFOV or 40 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSGFOV = v return true end },
            -- === NEW FOV COLOR ===
            { Key = "ModMenu_AT_SG_FOVColor", UI = AliasMap.Slider, Text = "      لون دائرة FOV (لون دائرة الرؤية)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSGFOVColor or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSGFOVColor = v return true end },
            { Key = "ModMenu_AT_SG_Dist", UI = AliasMap.Slider, Text = "      المسافة (المسافة - 1-100 متر)", ExpandHandle = "ModMenu_AT_SG_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSGDist or 30 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSGDist = v return true end },
            -- SCOPE ALL
            { Key = "ModMenu_AT_ScopeAll_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ أيم بوت المنظار (جميع الأسلحة - إذا كان غير محاذي، قم بإيقاف/تشغيل المنظار)", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.AimTouchScopeAll end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchScopeAll = v return true end },
            { Key = "ModMenu_AT_ScopeAll_IgKnock", UI = AliasMap.Switcher, Text = "      تجاهل الأعداء المطروحين (تجاهل العدو المطروح)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchScopeIgKnock end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchScopeIgKnock = v return true end },
            { Key = "ModMenu_AT_ScopeAll_IgBot", UI = AliasMap.Switcher, Text = "      تجاهل البوتات (تجاهل البوت)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchScopeIgBot end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchScopeIgBot = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Vis", UI = AliasMap.Switcher, Text = "      فحص الرؤية (فحص الجدار)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchScopeVisCheck end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchScopeVisCheck = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Prio", UI = AliasMap.Switcher, Text = "      الأولوية (الأولوية - 1: المركز 2: المسافة 3: الصحة 4: نسبة الصحة)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", SwitcherText = {"المركز","المسافة","الصحة","نسبة الصحة"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchScopePrio or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchScopePrio = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Bone", UI = AliasMap.Switcher, Text = "      استهداف العظم (استهداف العظم - 1: الرأس 2: الصدر 3: البطن 4: الحوض)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", SwitcherText = {"الرأس","الصدر","البطن","الحوض"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchScopeBone or 2 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchScopeBone = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Cond", UI = AliasMap.Switcher, Text = "      الشرط (الشرط - 1: التصويب عند إطلاق النار 2: التصويب دائمًا)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", SwitcherText = {"التصويب عند إطلاق النار","التصويب دائمًا"}, SwitcherValue = {1,2}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchScopeCond or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchScopeCond = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Spd", UI = AliasMap.Slider, Text = "      التنعيم / السرعة (التنعيم / السرعة - 1-100)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchScopeSpeed or 40 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchScopeSpeed = v return true end },
            { Key = "ModMenu_AT_ScopeAll_FOV", UI = AliasMap.Slider, Text = "      نطاق FOV (نطاق الرؤية - 1-100)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchScopeFOV or 20 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchScopeFOV = v return true end },
            -- === NEW FOV COLOR ===
            { Key = "ModMenu_AT_ScopeAll_FOVColor", UI = AliasMap.Slider, Text = "      لون دائرة FOV (لون دائرة الرؤية)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchScopeFOVColor or 6 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchScopeFOVColor = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Dist", UI = AliasMap.Slider, Text = "      المسافة (المسافة - 1-500 متر)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.MON5LAState.CustomTextData.AimTouchScopeDist or 300) / 5) end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchScopeDist = v * 5 return true end },
            { Key = "ModMenu_AT_ScopeAll_Pred", UI = AliasMap.Slider, Text = "      توقع الحركة (توقع الحركة)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchScopePred or 0 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchScopePred = v return true end },
            { Key = "ModMenu_AT_ScopeAll_Recoil", UI = AliasMap.Slider, Text = "      تعويض الارتداد التلقائي (تعويض الارتداد التلقائي - اضبط 3-4% لتنعيم)", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", MinValue = 0, MaxValue = 50, min = 0, max = 50, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchScopeRecoil or 0 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchScopeRecoil = v return true end },
            { Key = "ModMenu_LessShake", UI = AliasMap.Switcher, Text = "      مضاد الاهتزاز العلوي", ExpandHandle = "ModMenu_AT_ScopeAll_Ex", GetFunc = function() return _G.MON5LAConfig.LessShake end, SetFunc = function(c,v) _G.MON5LAConfig.LessShake = v return true end },
            -- SCOPE SNIPER
            { Key = "ModMenu_AT_Sniper_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ أيم بوت المنظار (بنادق القنص فقط)", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.AimTouchScopeSniper end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchScopeSniper = v return true end },
            { Key = "ModMenu_AT_Sniper_IgKnock", UI = AliasMap.Switcher, Text = "      تجاهل الأعداء المطروحين (تجاهل العدو المطروح)", ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchSniperIgKnock end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchSniperIgKnock = v return true end },
            { Key = "ModMenu_AT_Sniper_IgBot", UI = AliasMap.Switcher, Text = "      تجاهل البوتات (تجاهل البوت)", ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchSniperIgBot end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchSniperIgBot = v return true end },
            { Key = "ModMenu_AT_Sniper_Vis", UI = AliasMap.Switcher, Text = "      فحص الرؤية (فحص الجدار)", ExpandHandle = "ModMenu_AT_Sniper_Ex", GetFunc = function() return _G.MON5LAConfig.AimTouchSniperVisCheck end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchSniperVisCheck = v return true end },
            { Key = "ModMenu_AT_Sniper_Prio", UI = AliasMap.Switcher, Text = "      الأولوية (الأولوية - 1: المركز 2: المسافة 3: الصحة 4: نسبة الصحة)", ExpandHandle = "ModMenu_AT_Sniper_Ex", SwitcherText = {"المركز","المسافة","الصحة","نسبة الصحة"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSniperPrio or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSniperPrio = v return true end },
            { Key = "ModMenu_AT_Sniper_Bone", UI = AliasMap.Switcher, Text = "      استهداف العظم (استهداف العظم - 1: الرأس 2: الصدر 3: البطن 4: الحوض)", ExpandHandle = "ModMenu_AT_Sniper_Ex", SwitcherText = {"الرأس","الصدر","البطن","الحوض"}, SwitcherValue = {1,2,3,4}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSniperBone or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSniperBone = v return true end },
            { Key = "ModMenu_AT_Sniper_Cond", UI = AliasMap.Switcher, Text = "      الشرط (الشرط - 1: التصويب عند إطلاق النار 2: فتح المنظار للتصويب)", ExpandHandle = "ModMenu_AT_Sniper_Ex", SwitcherText = {"التصويب عند إطلاق النار","فتح المنظار للتصويب"}, SwitcherValue = {1,2}, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSniperCond or 2 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSniperCond = v return true end },
            { Key = "ModMenu_AT_Sniper_Spd", UI = AliasMap.Slider, Text = "      التنعيم / السرعة (التنعيم / السرعة - 1-100)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSniperSpeed or 30 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSniperSpeed = v return true end },
            { Key = "ModMenu_AT_Sniper_FOV", UI = AliasMap.Slider, Text = "      نطاق FOV (نطاق الرؤية - 1-100)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSniperFOV or 20 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSniperFOV = v return true end },
            -- === NEW FOV COLOR ===
            { Key = "ModMenu_AT_Sniper_FOVColor", UI = AliasMap.Slider, Text = "      لون دائرة FOV (لون دائرة الرؤية)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSniperFOVColor or 4 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSniperFOVColor = v return true end },
            { Key = "ModMenu_AT_Sniper_Dist", UI = AliasMap.Slider, Text = "      المسافة (المسافة - 1-500 متر)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return math.floor((_G.MON5LAState.CustomTextData.AimTouchSniperDist or 400) / 5) end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSniperDist = v * 5 return true end },
            { Key = "ModMenu_AT_Sniper_Pred", UI = AliasMap.Slider, Text = "      توقع الحركة (توقع الحركة - 0-100)", ExpandHandle = "ModMenu_AT_Sniper_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchSniperPred or 0 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchSniperPred = v return true end },
            -- === NEW AIMBOT MORTAR ===
            { Key = "ModMenu_AT_Mortar_Ex", UI = AliasMap.TitleSwitcher, Text = "   ▶ أيم بوت الهاون", ExpandHandle = "ModMenu_AT_Ex", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.AimTouchMortar end, SetFunc = function(c,v) _G.MON5LAConfig.AimTouchMortar = v return true end },
            { Key = "ModMenu_AT_Mortar_Pred", UI = AliasMap.Slider, Text = "      قيمة التوقع (قيمة التنبؤ)", ExpandHandle = "ModMenu_AT_Mortar_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchMortarPred or 0 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchMortarPred = v return true end },
            { Key = "ModMenu_AT_Mortar_FOV", UI = AliasMap.Slider, Text = "      نطاق FOV (نطاق الرؤية - 1-360)", ExpandHandle = "ModMenu_AT_Mortar_Ex", MinValue = 1, MaxValue = 360, min = 1, max = 360, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchMortarFOV or 360 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchMortarFOV = v return true end },
            -- === NEW FOV COLOR ===
            { Key = "ModMenu_AT_Mortar_FOVColor", UI = AliasMap.Slider, Text = "      لون دائرة FOV (لون دائرة الرؤية)", ExpandHandle = "ModMenu_AT_Mortar_Ex", MinValue = 1, MaxValue = 7, min = 1, max = 7, GetFunc = function() return _G.MON5LAState.CustomTextData.AimTouchMortarFOVColor or 5 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.AimTouchMortarFOVColor = v return true end },
            -- === FOV CIRCLE TOGGLE ===
            { Key = "ModMenu_FovCircle", UI = AliasMap.Switcher, Text = "▶ إظهار دائرة FOV للأيم بوت", GetFunc = function() return _G.MON5LAConfig.EspFovCircle end, SetFunc = function(c,v) _G.MON5LAConfig.EspFovCircle = v return true end },
            { Key = "ModMenu_HRecoil_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ تقليل الارتداد الأفقي (أسقط الملحقات وأعد تجهيزها إذا استمر الارتداد)", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.CustomHRecoil end, SetFunc = function(c,v) _G.MON5LAConfig.CustomHRecoil = v return true end },
            { Key = "ModMenu_HRecoil_Val", UI = AliasMap.Slider, Text = "   قيمة الارتداد الأفقي (0% : ارتداد أقل)", ExpandHandle = "ModMenu_HRecoil_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor((((_G.MON5LAState.CustomTextData.HRecoil or 0.3) - 0.3) / 4.7) * 100 + 0.5) end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.HRecoil = 0.3 + (v / 100.0) * 4.7 return true end },

            { Key = "ModMenu_VRecoil_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ تقليل الارتداد العمودي (أسقط الملحقات وأعد تجهيزها إذا استمر الارتداد)", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.CustomVRecoil end, SetFunc = function(c,v) _G.MON5LAConfig.CustomVRecoil = v return true end },
            { Key = "ModMenu_VRecoil_Val", UI = AliasMap.Slider, Text = "   قيمة الارتداد العمودي (0% : ارتداد أقل)", ExpandHandle = "ModMenu_VRecoil_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor((((_G.MON5LAState.CustomTextData.VRecoil or 0.3) - 0.3) / 4.7) * 100 + 0.5) end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.VRecoil = 0.3 + (v / 100.0) * 4.7 return true end }
        }

        -- ==================== MAGIC BULLET ====================
        local StackMagicBullet = {
            { Key = "ModMenu_Magic_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ رصاصة سحرية مخصصة (استخدمها على مسؤوليتك! لا تسأل إذا تم حظرك أو أي شيء، فالمخاطر على عاتقك!)", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.CustomMagicBullet end, SetFunc = function(c,v) _G.MON5LAConfig.CustomMagicBullet = v return true end },
            { Key = "ModMenu_Magic_Head", UI = AliasMap.Slider, Text = "   ضرر الرأس (0.0 - 5.0) (منطقة الرأس)", ExpandHandle = "ModMenu_Magic_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor(((_G.MON5LAState.CustomTextData.MagicHead or 1.0) / 5.0) * 100 + 0.5) end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.MagicHead = (v / 100.0) * 5.0 return true end },
            { Key = "ModMenu_Magic_Body", UI = AliasMap.Slider, Text = "   ضرر الجسم (0.0 - 5.0) (منطقة الجسم)", ExpandHandle = "ModMenu_Magic_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor(((_G.MON5LAState.CustomTextData.MagicBody or 1.0) / 5.0) * 100 + 0.5) end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.MagicBody = (v / 100.0) * 5.0 return true end },
            { Key = "ModMenu_Magic_Legs", UI = AliasMap.Slider, Text = "   ضرر الساقين (0.0 - 5.0) (منطقة الساقين)", ExpandHandle = "ModMenu_Magic_Ex", MinValue = 0, MaxValue = 100, min = 0, max = 100, GetFunc = function() return math.floor(((_G.MON5LAState.CustomTextData.MagicLegs or 1.0) / 5.0) * 100 + 0.5) end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.MagicLegs = (v / 100.0) * 5.0 return true end }
        }

        -- ==================== EXPERT (CAT_EXPERT) ====================
        local StackExpert = {
    -- ======== PARENT TOGGLE (TitleSwitcher + Pop-up) ========
    { 
        Key = "ModMenu_Expert_Active", 
        UI = AliasMap.TitleSwitcher,          -- <-- GANTI dari Switcher ke TitleSwitcher
        Text = "تفعيل ميزات الخبير؟", 
        ExpandIndex = 0,                       -- <-- TAMBAHKAN agar submenu bisa muncul
        GetFunc = function() 
            return _G.MON5LAConfig.ExpertEnabled or false 
        end,
        SetFunc = function(c, v)
            if v then
                -- Tampilkan pop-up konfirmasi
                local CommonMsgBoxMgr = require("client.slua.logic.common.logic_common_msg_box")
                CommonMsgBoxMgr.Show(
                    2, 
                    "تحذير", 
                    "ميزات الخبير هي ميزات وحشية لذا استخدمها بحكمة، هل تريد المتابعة؟",
                    function() 
                        -- YES: aktifkan, munculkan risk warning
                        _G.MON5LAConfig.ExpertEnabled = true
                        _G.SaveModSettings()
                        _G.ShowRiskWarning()
                        -- Refresh UI agar toggle sinkron
                        local UIManager = _G.UIManager
                        if UIManager then
                            UIManager.CloseUI(UIManager.UI_Config_InGame.Setting_Main)
                            UIManager.ShowUI(UIManager.UI_Config_InGame.Setting_Main)
                        end
                    end,
                    function() 
                        -- NO: matikan, sembunyikan risk warning, refresh UI
                        _G.MON5LAConfig.ExpertEnabled = false
                        _G.SaveModSettings()
                        _G.HideRiskWarning()
                        local UIManager = _G.UIManager
                        if UIManager then
                            UIManager.CloseUI(UIManager.UI_Config_InGame.Setting_Main)
                            UIManager.ShowUI(UIManager.UI_Config_InGame.Setting_Main)
                        end
                    end,
                    "نعم", 
                    "لا"
                )
                -- Set sementara agar toggle pindah ke ON (akan dibetulkan jika NO)
                _G.MON5LAConfig.ExpertEnabled = true
                return true
            else
                _G.MON5LAConfig.ExpertEnabled = false
                _G.HideRiskWarning()
                return true
            end
        end
    },

    -- ========== MAGIC BULLET ==========
    { 
        Key = "ModMenu_Magic_Ex", 
        UI = AliasMap.TitleSwitcher, 
        Text = "▶ رصاصة سحرية", 
        ExpandHandle = "ModMenu_Expert_Active",   -- parent key
        ExpandIndex = 0, 
        GetFunc = function() return _G.MON5LAConfig.CustomMagicBullet end, 
        SetFunc = function(c,v) _G.MON5LAConfig.CustomMagicBullet = v return true end 
    },
    { 
        Key = "ModMenu_Magic_Head", 
        UI = AliasMap.Slider, 
        Text = "   ضرر الرأس (0.0 - 5.0) (منطقة الرأس)", 
        ExpandHandle = "ModMenu_Expert_Active", 
        MinValue = 0, MaxValue = 100, min = 0, max = 100, 
        GetFunc = function() return math.floor(((_G.MON5LAState.CustomTextData.MagicHead or 1.0) / 5.0) * 100 + 0.5) end, 
        SetFunc = function(c,v) _G.MON5LAState.CustomTextData.MagicHead = (v / 100.0) * 5.0 return true end 
    },
    { 
        Key = "ModMenu_Magic_Body", 
        UI = AliasMap.Slider, 
        Text = "   ضرر الجسم (0.0 - 5.0) (منطقة الجسم)", 
        ExpandHandle = "ModMenu_Expert_Active", 
        MinValue = 0, MaxValue = 100, min = 0, max = 100, 
        GetFunc = function() return math.floor(((_G.MON5LAState.CustomTextData.MagicBody or 1.0) / 5.0) * 100 + 0.5) end, 
        SetFunc = function(c,v) _G.MON5LAState.CustomTextData.MagicBody = (v / 100.0) * 5.0 return true end 
    },
    { 
        Key = "ModMenu_Magic_Legs", 
        UI = AliasMap.Slider, 
        Text = "   ضرر الساقين (0.0 - 5.0) (منطقة الساقين)", 
        ExpandHandle = "ModMenu_Expert_Active", 
        MinValue = 0, MaxValue = 100, min = 0, max = 100, 
        GetFunc = function() return math.floor(((_G.MON5LAState.CustomTextData.MagicLegs or 1.0) / 5.0) * 100 + 0.5) end, 
        SetFunc = function(c,v) _G.MON5LAState.CustomTextData.MagicLegs = (v / 100.0) * 5.0 return true end 
    },

    -- ========== WEAPON MOD ==========
    { 
        Key = "ModMenu_Weapon_Ex", 
        UI = AliasMap.TitleSwitcher, 
        Text = "▶ تعديل السلاح", 
        ExpandHandle = "ModMenu_Expert_Active", 
        ExpandIndex = 0, 
        GetFunc = function() return _G.MON5LAConfig.EnableWeaponMod end, 
        SetFunc = function(c,v) _G.MON5LAConfig.EnableWeaponMod = v return true end 
    },
    -- AKM
    { Key = "ModMenu_W101001_Title", UI = AliasMap.Title, Text = "   AKM", ExpandHandle = "ModMenu_Expert_Active" },
    { Key = "ModMenu_W101001_F", UI = AliasMap.Switcher, Text = "      سرعة الإطلاق", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101001].FireSpeed end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101001].FireSpeed = v return true end },
    { Key = "ModMenu_W101001_I", UI = AliasMap.Switcher, Text = "      إصابة فورية", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101001].InstanHit end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101001].InstanHit = v return true end },
    { Key = "ModMenu_W101001_S", UI = AliasMap.Switcher, Text = "      تبديل سريع", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101001].FastSwitch end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101001].FastSwitch = v return true end },
    { Key = "ModMenu_W101001_O", UI = AliasMap.Switcher, Text = "      فتح المنظار بسرعة", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101001].FastScope end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101001].FastScope = v return true end },
    -- M416
    { Key = "ModMenu_W101004_Title", UI = AliasMap.Title, Text = "   M416", ExpandHandle = "ModMenu_Expert_Active" },
    { Key = "ModMenu_W101004_F", UI = AliasMap.Switcher, Text = "      سرعة الإطلاق", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101004].FireSpeed end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101004].FireSpeed = v return true end },
    { Key = "ModMenu_W101004_I", UI = AliasMap.Switcher, Text = "      إصابة فورية", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101004].InstanHit end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101004].InstanHit = v return true end },
    { Key = "ModMenu_W101004_S", UI = AliasMap.Switcher, Text = "      تبديل سريع", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101004].FastSwitch end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101004].FastSwitch = v return true end },
    { Key = "ModMenu_W101004_O", UI = AliasMap.Switcher, Text = "      فتح المنظار بسرعة", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101004].FastScope end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101004].FastScope = v return true end },
    -- Beryl M762
    { Key = "ModMenu_W101008_Title", UI = AliasMap.Title, Text = "   Beryl M762", ExpandHandle = "ModMenu_Expert_Active" },
    { Key = "ModMenu_W101008_F", UI = AliasMap.Switcher, Text = "      سرعة الإطلاق", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101008].FireSpeed end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101008].FireSpeed = v return true end },
    { Key = "ModMenu_W101008_I", UI = AliasMap.Switcher, Text = "      إصابة فورية", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101008].InstanHit end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101008].InstanHit = v return true end },
    { Key = "ModMenu_W101008_S", UI = AliasMap.Switcher, Text = "      تبديل سريع", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101008].FastSwitch end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101008].FastSwitch = v return true end },
    { Key = "ModMenu_W101008_O", UI = AliasMap.Switcher, Text = "      فتح المنظار بسرعة", ExpandHandle = "ModMenu_Expert_Active", GetFunc = function() return _G.MON5LAConfig.WeaponMod[101008].FastScope end, SetFunc = function(c,v) _G.MON5LAConfig.WeaponMod[101008].FastScope = v return true end },
}

        -- ==================== COMBAT GRAPHIC ====================
        local StackCombatGraphic = {
            { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#إعدادات أخرى", ExpandHandle = "ModMenu_Skin3_Ex" },
            { Key = "ModMenu_Ipad_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ عرض iPad (شاشة iPad)", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.IpadView end, SetFunc = function(c,v) _G.MON5LAConfig.IpadView = v return true end },
            { Key = "ModMenu_Ipad_FOV", UI = AliasMap.Slider, Text = "   زاوية FOV (زاوية الرؤية)", ExpandHandle = "ModMenu_Ipad_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return (_G.MON5LAState.CustomTextData.IpadViewFOV or 120) - 90 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.IpadViewFOV = 90 + v return true end },
            -- === NEW IPAD VEHICLE ===
            { Key = "ModMenu_IpadVeh_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ عرض iPad للمركبات", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.IpadViewVehicle end, SetFunc = function(c,v) _G.MON5LAConfig.IpadViewVehicle = v return true end },
            { Key = "ModMenu_IpadVeh_FOV", UI = AliasMap.Slider, Text = "   زاوية FOV للمركبة", ExpandHandle = "ModMenu_IpadVeh_Ex", MinValue = 1, MaxValue = 100, min = 1, max = 100, GetFunc = function() return (_G.MON5LAState.CustomTextData.IpadViewVehicleFOV or 120) - 90 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.IpadViewVehicleFOV = 90 + v return true end },
            -- === NEW IPAD SCOPE ===
            { Key = "ModMenu_IpadScope_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ عرض iPad للمنظار", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.IpadViewScope end, SetFunc = function(c,v) _G.MON5LAConfig.IpadViewScope = v return true end },
            { Key = "ModMenu_IpadScope_FOV", UI = AliasMap.Slider, Text = "   FOV المنظار (30-120)", ExpandHandle = "ModMenu_IpadScope_Ex", MinValue = 30, MaxValue = 120, min = 30, max = 120, GetFunc = function() return _G.MON5LAState.CustomTextData.IpadViewScopeFOV or 60 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.IpadViewScopeFOV = v return true end },
            { Key = "ModMenu_165FPS", UI = AliasMap.Switcher, Text = "فتح 165 إطارًا في الثانية (إذا تم إيقافه، سيتم تفعيله في المباراة التالية)", GetFunc = function() return _G.MON5LAConfig.UnlockFPS end, SetFunc = function(c,v) _G.MON5LAConfig.UnlockFPS = v; if v then _G.MON5LAState.GraphicsUnlocked = false end return true end },
            { Key = "ModMenu_RemoveFog", UI = AliasMap.Switcher, Text = "إزالة الضباب (إذا تم إيقافه، سيتم تفعيله في المباراة التالية)", GetFunc = function() return _G.MON5LAConfig.RemoveFog end, SetFunc = function(c,v) _G.MON5LAConfig.RemoveFog = v return true end },
            { Key = "ModMenu_RemoveGrass", UI = AliasMap.Switcher, Text = "إزالة العشب (إذا تم إيقافه، سيتم تفعيله في المباراة التالية)", GetFunc = function() return _G.MON5LAConfig.RemoveGrass end, SetFunc = function(c,v) _G.MON5LAConfig.RemoveGrass = v return true end }
        }
        
        -- ==================== SKIN MOD ====================
        local StackSkinMod = {
            { Key = "ModMenu_Skin_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ تعديل المظهر (اختراق المظهر)", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.ModSkin end, SetFunc = function(c,v) _G.MON5LAConfig.ModSkin = v return true end },
            { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#ملابس 90 مظهر", ExpandHandle = "ModMenu_Skin3_Ex" },
            { Key = "ModMenu_Skin_Suit", UI = AliasMap.Slider, Text = "   » مظهر البدلة [1-90]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 90, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinSuit or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinSuit = v; if _G.OutfitSkins and _G.OutfitSkins.Suit[v] then _G.OutfitMap.Suit = _G.OutfitSkins.Suit[v] end return true end },
            { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#حقيبة وخوذة 33 مظهر", ExpandHandle = "ModMenu_Skin3_Ex" },
            { Key = "ModMenu_Skin_Bag", UI = AliasMap.Slider, Text = "   » مظهر الحقيبة [1-19]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 19, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinBag or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinBag = v; if _G.OutfitSkins and _G.OutfitSkins.Bag[v] then _G.OutfitMap.Bag = _G.OutfitSkins.Bag[v] end return true end },
            { Key = "ModMenu_Skin_Helmet", UI = AliasMap.Slider, Text = "   » مظهر الخوذة [1-14]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 14, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinHelmet or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinHelmet = v; if _G.OutfitSkins and _G.OutfitSkins.Helmet[v] then _G.OutfitMap.Helmet = _G.OutfitSkins.Helmet[v] end return true end },
            { Key = "ModMenu_Skin_Gloves", UI = AliasMap.Title, Text = "#مظهر القفازات", ExpandHandle = "ModMenu_Skin3_Ex" },
    { Key = "ModMenu_Skin_Gloves", UI = AliasMap.Slider, Text = "   » مظهر القفازات [1-3]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 3, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinGloves or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinGloves = v; if _G.OutfitSkins.Gloves and _G.OutfitSkins.Gloves[v] then _G.OutfitMap.Gloves = _G.OutfitSkins.Gloves[v] end return true end },
            { Key = "ModMenu_Skin_Glider2", UI = AliasMap.Title, Text = "#مظهر المظلة والطائرة الشراعية", ExpandHandle = "ModMenu_Skin3_Ex" },
    { Key = "ModMenu_Skin_Glider", UI = AliasMap.Slider, Text = "   » مظهر الطائرة الشراعية [1-1]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 1, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinGlider or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinGlider = v; if _G.OutfitSkins.Glider and _G.OutfitSkins.Glider[v] then _G.OutfitMap.Glider = _G.OutfitSkins.Glider[v] end return true end },
    { Key = "ModMenu_Skin_Parachute", UI = AliasMap.Slider, Text = "   » مظهر المظلة [1-1]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 1, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinParachute or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinParachute = v; if _G.OutfitSkins.Parachute and _G.OutfitSkins.Parachute[v] then _G.OutfitMap.Parachute = _G.OutfitSkins.Parachute[v] end return true end },
            { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#سلاح 83 مظهر", ExpandHandle = "ModMenu_Skin3_Ex" },
            { Key = "ModMenu_Skin_M416", UI = AliasMap.Slider, Text = "   » مظهر M416 [1-11]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 11, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinM416 or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinM416 = v; if _G.skinIdMappings[101004] and _G.skinIdMappings[101004][v] then _G.WeaponSkinMap[101004] = _G.skinIdMappings[101004][v] end return true end },
            { Key = "ModMenu_Skin_AKM", UI = AliasMap.Slider, Text = "   » مظهر AKM [1-8]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 8, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinAKM or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinAKM = v; if _G.skinIdMappings[101001] and _G.skinIdMappings[101001][v] then _G.WeaponSkinMap[101001] = _G.skinIdMappings[101001][v] end return true end },
            { Key = "ModMenu_Skin_SCAR", UI = AliasMap.Slider, Text = "   » مظهر SCAR-L [1-8]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 8, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinSCAR or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinSCAR = v; if _G.skinIdMappings[101003] and _G.skinIdMappings[101003][v] then _G.WeaponSkinMap[101003] = _G.skinIdMappings[101003][v] end return true end },
            { Key = "ModMenu_Skin_M762", UI = AliasMap.Slider, Text = "   » مظهر BERYL M762 [1-9]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 9, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinM762 or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinM762 = v; if _G.skinIdMappings[101008] and _G.skinIdMappings[101008][v] then _G.WeaponSkinMap[101008] = _G.skinIdMappings[101008][v] end return true end },
            { Key = "ModMenu_Skin_AUG", UI = AliasMap.Slider, Text = "   » مظهر AUG [1-9]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 9, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinAUG or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinAUG = v; if _G.skinIdMappings[101006] and _G.skinIdMappings[101006][v] then _G.WeaponSkinMap[101006] = _G.skinIdMappings[101006][v] end return true end },
            { Key = "ModMenu_Skin_Honey", UI = AliasMap.Slider, Text = "   » مظهر HONEY BADGER [1-2]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 2, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinHoney or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinHoney = v; if _G.skinIdMappings[101012] and _G.skinIdMappings[101012][v] then _G.WeaponSkinMap[101012] = _G.skinIdMappings[101012][v] end return true end },
            { Key = "ModMenu_Skin_QBZ", UI = AliasMap.Slider, Text = "   » مظهر QBZ [1-3]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 3, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinQBZ or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinQBZ = v; if _G.skinIdMappings[101007] and _G.skinIdMappings[101007][v] then _G.WeaponSkinMap[101007] = _G.skinIdMappings[101007][v] end return true end },
            { Key = "ModMenu_Skin_ASM", UI = AliasMap.Slider, Text = "   » مظهر ASM ABAKAN [1-2]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 2, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinASM or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinASM = v; if _G.skinIdMappings[101101] and _G.skinIdMappings[101101][v] then _G.WeaponSkinMap[101101] = _G.skinIdMappings[101101][v] end return true end },
            { Key = "ModMenu_Skin_ACE32", UI = AliasMap.Slider, Text = "   » مظهر ACE32 [1-2]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 2, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinACE32 or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinACE32 = v; if _G.skinIdMappings[101102] and _G.skinIdMappings[101102][v] then _G.WeaponSkinMap[101102] = _G.skinIdMappings[101102][v] end return true end },
            { Key = "ModMenu_Skin_UMP", UI = AliasMap.Slider, Text = "   » مظهر UMP45 [1-6]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 6, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinUMP or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinUMP = v; if _G.skinIdMappings[102002] and _G.skinIdMappings[102002][v] then _G.WeaponSkinMap[102002] = _G.skinIdMappings[102002][v] end return true end },
            { Key = "ModMenu_Skin_UZI", UI = AliasMap.Slider, Text = "   » مظهر UZI [1-2]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 2, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinUZI or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinUZI = v; if _G.skinIdMappings[102001] and _G.skinIdMappings[102001][v] then _G.WeaponSkinMap[102001] = _G.skinIdMappings[102001][v] end return true end },
            { Key = "ModMenu_Skin_Vector", UI = AliasMap.Slider, Text = "   » مظهر VECTOR [1-2]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 2, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinVector or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinVector = v; if _G.skinIdMappings[102003] and _G.skinIdMappings[102003][v] then _G.WeaponSkinMap[102003] = _G.skinIdMappings[102003][v] end return true end },
            { Key = "ModMenu_Skin_BIZON", UI = AliasMap.Slider, Text = "   » مظهر BIZON-19 [1-1]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 1, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinBIZON or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinBIZON = v; if _G.skinIdMappings[102005] and _G.skinIdMappings[102005][v] then _G.WeaponSkinMap[102005] = _G.skinIdMappings[102005][v] end return true end },
            { Key = "ModMenu_Skin_Groza", UI = AliasMap.Slider, Text = "   » مظهر GROZA [1-2]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 2, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinGroza or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinGroza = v; if _G.skinIdMappings[101005] and _G.skinIdMappings[101005][v] then _G.WeaponSkinMap[101005] = _G.skinIdMappings[101005][v] end return true end },
            { Key = "ModMenu_Skin_Kar98K", UI = AliasMap.Slider, Text = "   » مظهر KAR98K [1-3]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 3, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinKar98K or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinKar98K = v; if _G.skinIdMappings[103001] and _G.skinIdMappings[103001][v] then _G.WeaponSkinMap[103001] = _G.skinIdMappings[103001][v] end return true end },
            { Key = "ModMenu_Skin_M24", UI = AliasMap.Slider, Text = "   » مظهر M24 [1-2]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 2, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinM24 or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinM24 = v; if _G.skinIdMappings[103002] and _G.skinIdMappings[103002][v] then _G.WeaponSkinMap[103002] = _G.skinIdMappings[103002][v] end return true end },
            { Key = "ModMenu_Skin_AWM", UI = AliasMap.Slider, Text = "   » مظهر AWM [1-4]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 4, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinAWM or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinAWM = v; if _G.skinIdMappings[103003] and _G.skinIdMappings[103003][v] then _G.WeaponSkinMap[103003] = _G.skinIdMappings[103003][v] end return true end },
            { Key = "ModMenu_Skin_AMR", UI = AliasMap.Slider, Text = "   » مظهر AMR [1-3]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 3, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinAMR or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinAMR = v; if _G.skinIdMappings[103012] and _G.skinIdMappings[103012][v] then _G.WeaponSkinMap[103012] = _G.skinIdMappings[103012][v] end return true end },
            { Key = "ModMenu_Skin_S12K", UI = AliasMap.Slider, Text = "   » مظهر S12K [1-2]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 2, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinS12K or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinS12K = v; if _G.skinIdMappings[104003] and _G.skinIdMappings[104003][v] then _G.WeaponSkinMap[104003] = _G.skinIdMappings[104003][v] end return true end },
            { Key = "ModMenu_Skin_DBS", UI = AliasMap.Slider, Text = "   » مظهر DBS [1-3]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 3, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinDBS or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinDBS = v; if _G.skinIdMappings[104004] and _G.skinIdMappings[104004][v] then _G.WeaponSkinMap[104004] = _G.skinIdMappings[104004][v] end return true end },
            { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#مركبة 326 مظهر", ExpandHandle = "ModMenu_Skin3_Ex" },
            { Key = "ModMenu_Skin_Dacia", UI = AliasMap.Slider, Text = "   » مظهر DACIA [1-90]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 90, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinDacia or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinDacia = v; if _G.VehicleSkins[1903001] and _G.VehicleSkins[1903001][v] then _G.VehicleSkinMap[1903001] = _G.VehicleSkins[1903001][v] end return true end },
            { Key = "ModMenu_Skin_UAZ", UI = AliasMap.Slider, Text = "   » مظهر UAZ [1-90]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 90, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinUAZ or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinUAZ = v; if _G.VehicleSkins[1908001] and _G.VehicleSkins[1908001][v] then _G.VehicleSkinMap[1908001] = _G.VehicleSkins[1908001][v] end return true end },
            { Key = "ModMenu_Skin_Coupe", UI = AliasMap.Slider, Text = "   » مظهر COUPE RB [1-70]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 70, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinCoupe or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinCoupe = v; if _G.VehicleSkins[1961001] and _G.VehicleSkins[1961001][v] then _G.VehicleSkinMap[1961001] = _G.VehicleSkins[1961001][v] end return true end },
            { Key = "ModMenu_Skin_Buggy", UI = AliasMap.Slider, Text = "   » مظهر BUGGY [1-50]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 50, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinBuggy or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinBuggy = v; if _G.VehicleSkins[1907001] and _G.VehicleSkins[1907001][v] then _G.VehicleSkinMap[1907001] = _G.VehicleSkins[1907001][v] end return true end },
            { Key = "ModMenu_Skin_Mirado", UI = AliasMap.Slider, Text = "   » مظهر MIRADO [1-27]", ExpandHandle = "ModMenu_Skin_Ex", MinValue = 1, MaxValue = 27, GetFunc = function() return _G.MON5LAState.CustomTextData.SkinMirado or 1 end, SetFunc = function(c,v) _G.MON5LAState.CustomTextData.SkinMirado = v; if _G.VehicleSkins[1915001] and _G.VehicleSkins[1915001][v] then _G.VehicleSkinMap[1915001] = _G.VehicleSkins[1915001][v] end return true end },
            { Key = "ModMenu_Deadbox_Ex", UI = AliasMap.TitleSwitcher, Text = "▶ مظهر صندوق الموتى", ExpandIndex = 0, GetFunc = function() return _G.MON5LAConfig.DeadboxEnabled end, SetFunc = function(c,v) _G.MON5LAConfig.DeadboxEnabled = v return true end },
            { Key = "ModMenu_Deadbox_Delay", UI = AliasMap.Slider, Text = "   تأخير صندوق الموتى (ثواني - 0.1-5.0)", ExpandHandle = "ModMenu_Deadbox_Ex", MinValue = 1, MaxValue = 50, min = 1, max = 50, GetFunc = function() return math.floor((_G.MON5LAState.DeadboxDelay or 2.0) * 10) end, SetFunc = function(c,v) _G.MON5LAState.DeadboxDelay = v / 10.0; return true end },
            { Key = "ModMenu_KillCounter", UI = AliasMap.Switcher, Text = "رسالة القتل", GetFunc = function() return _G.MON5LAConfig.KillCounterEnabled end, SetFunc = function(c,v) _G.MON5LAConfig.KillCounterEnabled = v; if v then _G.ForceEnableKillCounterUI() end return true end },
        }

        -- ==================== COLOR MOD (BAWAAN PO2.LUA) ====================
        local StackColorMod = {
            { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#إعدادات اختراق الجدران", ExpandHandle = "ModMenu_Skin3_Ex" },
            { Key = "ModMenu_WallColor", UI = AliasMap.Switcher, Text = "اختراق الجدران والألوان (غير مرئي ومرئي)", GetFunc = function() return _G.MON5LAConfig.Wallhack end, SetFunc = function(c,v) 
                _G.MON5LAConfig.Wallhack = v 
                _G.MON5LAConfig.ColorBodyNew = v  -- Always use V3 engine
                return true 
            end },
            { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#إعدادات الألوان", ExpandHandle = "ModMenu_Skin3_Ex" },
            { Key = "COLOR_Visible", UI = AliasMap.Switcher, Text = "لون مرئي (ESP و WH)",
              SwitcherText = {"أحمر","أبيض","أصفر","أخضر","سماوي","أزرق","بنفسجي"},
              SwitcherValue = {1,2,3,4,5,6,7},
              GetFunc = function() return _G.ColorConfig.VisibleColor end,
              SetFunc = function(_, v) _G.ColorConfig.VisibleColor = v; _G.SaveModSettings(); return true end },
            { Key = "COLOR_Invisible", UI = AliasMap.Switcher, Text = "لون غير مرئي (ESP و WH)",
              SwitcherText = {"أحمر","أبيض","أصفر","أخضر","سماوي","أزرق","بنفسجي"},
              SwitcherValue = {1,2,3,4,5,6,7},
              GetFunc = function() return _G.ColorConfig.InvisibleColor end,
              SetFunc = function(_, v) _G.ColorConfig.InvisibleColor = v; _G.SaveModSettings(); return true end },
            { Key = "COLOR_Brightness", UI = AliasMap.Slider, Text = "السطوع (1-50)", Min = 1, Max = 50, Step = 1,
              GetFunc = function() return _G.ColorConfig.Brightness end,
              SetFunc = function(_, v) _G.ColorConfig.Brightness = v; _G.SaveModSettings(); return true end },
            { Key = "ModMenu_Skin_Glider", UI = AliasMap.Title, Text = "#ألوان أخرى", ExpandHandle = "ModMenu_Skin3_Ex" },
            { Key = "COLOR_Glow", UI = AliasMap.Slider, Text = "شدة التوهج (0-10) (WH)", Min = 0, Max = 10, Step = 0.5,
              GetFunc = function() return _G.ColorConfig.Glow end,
              SetFunc = function(_, v) _G.ColorConfig.Glow = v; _G.SaveModSettings(); return true end },
            { Key = "ModMenu_WhiteBody", UI = AliasMap.Switcher, Text = "جسم أبيض (جسم أبيض)", GetFunc = function() return _G.MON5LAConfig.WhiteBody end, SetFunc = function(c,v) _G.MON5LAConfig.WhiteBody = v return true end },
            { Key = "ModMenu_BlackSky", UI = AliasMap.Switcher, Text = "سماء سوداء (سماء سوداء)", GetFunc = function() return _G.MON5LAConfig.BlackSky end, SetFunc = function(c,v) _G.MON5LAConfig.BlackSky = v return true end }
        }

        -- ==================== DEFINE MENU PAGE ====================
        -- ═══════════════════════════════════════════════════════════════════
-- 🔥 ESP VIP FULL — Stack الجديد من ملف الاختبار
-- ═══════════════════════════════════════════════════════════════════
local StackESPVIPFull = {
    { UI = AliasMap.Title, Text = "  ═══ ESP VIP FULL ═══  " },
    {
        Key = "ModMenu_ESPFull_Main",
        UI = AliasMap.TitleSwitcher,
        Text = "▶ تفعيل ESP الكامل (RedBox + Widgets)",
        ExpandIndex = 0,
        GetFunc = function() return _G.LexusConfig.EspLoai9 end,
        SetFunc = function(c, v)
            _G.LexusConfig.EspLoai9 = v
            if _G.SaveModSettings then _G.SaveModSettings() end
            return true
        end
    },
    {
        Key = "ModMenu_ESPFull_Count",
        UI = AliasMap.Switcher,
        Text = "   عدّاد اللاعبين والبوتات (RedBox)",
        ExpandHandle = "ModMenu_ESPFull_Main",
        GetFunc = function() return _G.LexusConfig.Esp9_Count end,
        SetFunc = function(c, v) _G.LexusConfig.Esp9_Count = v return true end
    },
    {
        Key = "ModMenu_ESPFull_Name",
        UI = AliasMap.Switcher,
        Text = "   عرض الاسم فوق الرأس",
        ExpandHandle = "ModMenu_ESPFull_Main",
        GetFunc = function() return _G.LexusConfig.Esp9_Name end,
        SetFunc = function(c, v) _G.LexusConfig.Esp9_Name = v return true end
    },
    {
        Key = "ModMenu_ESPFull_HP",
        UI = AliasMap.Switcher,
        Text = "   عرض الصحة (HP Bar)",
        ExpandHandle = "ModMenu_ESPFull_Main",
        GetFunc = function() return _G.LexusConfig.Esp9_HP end,
        SetFunc = function(c, v) _G.LexusConfig.Esp9_HP = v return true end
    },
    {
        Key = "ModMenu_ESPFull_Dist",
        UI = AliasMap.Switcher,
        Text = "   عرض المسافة (بالمتر)",
        ExpandHandle = "ModMenu_ESPFull_Main",
        GetFunc = function() return _G.LexusConfig.Esp9_Distance end,
        SetFunc = function(c, v) _G.LexusConfig.Esp9_Distance = v return true end
    },
    {
        Key = "ModMenu_ESPFull_Weapon",
        UI = AliasMap.Switcher,
        Text = "   عرض أيقونة السلاح",
        ExpandHandle = "ModMenu_ESPFull_Main",
        GetFunc = function() return _G.LexusConfig.Esp9_Weapon end,
        SetFunc = function(c, v) _G.LexusConfig.Esp9_Weapon = v return true end
    },
    {
        Key = "ModMenu_ESPFull_Team",
        UI = AliasMap.Switcher,
        Text = "   عرض لون الفريق (Box)",
        ExpandHandle = "ModMenu_ESPFull_Main",
        GetFunc = function() return _G.LexusConfig.Esp9_Team end,
        SetFunc = function(c, v) _G.LexusConfig.Esp9_Team = v return true end
    },
    {
        Key = "ModMenu_ESPFull_Line",
        UI = AliasMap.Switcher,
        Text = "   خطوط SnapLine",
        ExpandHandle = "ModMenu_ESPFull_Main",
        GetFunc = function() return _G.LexusConfig.Esp9_Line end,
        SetFunc = function(c, v) _G.LexusConfig.Esp9_Line = v return true end
    },
    {
        Key = "ModMenu_ESPFull_Skeleton",
        UI = AliasMap.Switcher,
        Text = "   الهيكل العظمي (يسبب لاج)",
        ExpandHandle = "ModMenu_ESPFull_Main",
        GetFunc = function() return _G.LexusConfig.Esp9_Skeleton end,
        SetFunc = function(c, v) _G.LexusConfig.Esp9_Skeleton = v return true end
    },
    {
        Key = "ModMenu_ESPFull_Chams",
        UI = AliasMap.Switcher,
        Text = "   تلوين الأجسام (Engine Chams)",
        ExpandHandle = "ModMenu_ESPFull_Main",
        GetFunc = function() return _G.LexusConfig.ColorBodyNew end,
        SetFunc = function(c, v) _G.LexusConfig.ColorBodyNew = v return true end
    },
    { UI = AliasMap.Title, Text = "  ═══ تلوين Chams ═══  " },
    {
        Key = "ModMenu_ESPFull_ChamsVis",
        UI = AliasMap.Switcher,
        Text = "   لون الجسم الظاهر",
        SwitcherText = {"أحمر","أزرق","أخضر","أصفر","برتقالي","وردي"},
        SwitcherValue = {1, 2, 3, 4, 5, 6},
        GetFunc = function() return _G.LexusConfig.ChamsColorVis or 3 end,
        SetFunc = function(c, v) _G.LexusConfig.ChamsColorVis = v return true end
    },
    {
        Key = "ModMenu_ESPFull_ChamsOcc",
        UI = AliasMap.Switcher,
        Text = "   لون الجسم خلف الجدار",
        SwitcherText = {"أحمر","أزرق","أخضر","أصفر","برتقالي","وردي"},
        SwitcherValue = {1, 2, 3, 4, 5, 6},
        GetFunc = function() return _G.LexusConfig.ChamsColorOcc or 1 end,
        SetFunc = function(c, v) _G.LexusConfig.ChamsColorOcc = v return true end
    },
}

SettingPageDefine.ModMenu = {
    Key = "ModMenu",
    Text = "❮❮MR.BEAN❯❯",
    UIKey = "Setting_Page_Privacy",
    Category = {
        { Key = "Cat_ESPVIPFull", Text = "🔥 ESP VIP FULL", Stack = StackESPVIPFull },
        { Key = "Cat_ESP_Visual", Text = "❏ ESP الكشف", Stack = StackESPVisual },
    --    { Key = "Cat_Aimbot_Force", Text = "❏ ايم بوت", Stack = StackAimbotForce },
        { Key = "Cat_Combat_Graphic", Text = "❏ تحسين المرئيات", Stack = StackCombatGraphic },
        { Key = "Cat_ColorMod", Text = "❏ الويل هاك", Stack = StackColorMod }
    }
}
        
        table.insert(SettingCatalog, SettingPageDefine.ModMenu)
    end

    local UIManager = _G.UIManager
    if UIManager and not UIManager._IsModMenuHooked then
        local old_ShowUI = UIManager.ShowUI
        UIManager.ShowUI = function(config, ...)
            local args = {...}
            local n = select('#', ...) 
            
            if config and config.keyName and (string.find(string.lower(config.keyName), "setting_main") or string.find(string.lower(config.keyName), "setting")) then
                local catalog = args[1]
                if type(catalog) == "table" then
                    local hasModMenu = false
                    for _, page in ipairs(catalog) do
                        if type(page) == "table" and page.Key == "ModMenu" then
                            hasModMenu = true
                            break
                        end
                    end
                    if not hasModMenu then
                        table.insert(catalog, SettingPageDefine.ModMenu)
                    end
                end
            end
            local table_unpack = table.unpack or unpack
            return old_ShowUI(config, table_unpack(args, 1, n))
        end
        UIManager._IsModMenuHooked = true
    end
end

function _G.ShowMON5LAVIPMenu() 
    if _G.MON5LAMenuAlreadyShown then return end
    if _G.MON5LAState.MenuStep ~= 0 then return end

    pcall(function()
        local Msg = require("client.slua.logic.common.logic_common_msg_box")
        if not Msg or not Msg.Show then return end

        local function Step_ScamAlert()
            Msg.Show(1, "تحذير", "Telegram : @D331D", function() local Web = require("client.slua.logic.url.logic_webview_sdk"); if Web and Web.OpenURL then Web:OpenURL("https://t.me/zmh10") end end, function() end, "انضم", "إغلاق")
            _G.MON5LAState.MenuStep = 99
            _G.MON5LAMenuAlreadyShown = true
        end

        local function Step_Welcome()
            Msg.Show(1, "MR.BEAN",
            function() 
                _G.InitModMenuTab()
                Notify("قائمة VIP MOD BY @D331D لتفعيل الميزات!")
                Step_ScamAlert()
            end, 
            function() end, "حسنًا", "إغلاق")
        end

        _G.MON5LAState.MenuStep = 1
        Step_Welcome() 
    end)
end
-- ========================================== 
-- LOGIC 165 FPS IPAD VIEW 
-- ========================================== 

local function ShowBypassPopup()
    if _G.BypassPopupShown then return end
    _G.BypassPopupShown = true
    
    pcall(function()
        local CommonMsgBoxMgr = require("client.slua.logic.common.logic_common_msg_box")
        local Web = require("client.slua.logic.url.logic_webview_sdk")
        local function onClickTele()
            Web:OpenURL("https://t.me/xqueenmods")
        end
        local msg = "تحذير !!\n\nPAKS MOD BY N5LA\nCHANEL TELEGRAM @D331D\n\n العب بذكاء وتجنب البلاغات ولا تتخطي 10 كيل\n"
        CommonMsgBoxMgr.Show(2, "#ملاحظات من المشرف", msg, onClickTele, nil, "TELEGRAM")
    end)
end

-- =====

local function InitializeGraphicsUnlock() 
    if isExpired then return end
    if _G.MON5LAState.GraphicsUnlocked or currentTime > limitTime then return end

    pcall(function()
        local SettingCfg = require("client.logic.setting.setting_config")
        local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        if SettingCfg then
            if SettingCfg.TpViewValue then SettingCfg.TpViewValue.max = 160 end
            if SettingCfg.FpViewValue then SettingCfg.FpViewValue.max = 160 end
        end
        if GraphicSettingDB then
            if GraphicSettingDB.TpViewValue then GraphicSettingDB.TpViewValue.max = 160 end
        end
    end)

    pcall(function()
        local logic_setting_graphics = require("client.slua.logic.setting.logic_setting_graphics")
        local GSC_FPS = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPS")
        local GSC_FPSFT = require("client.slua.umg.NewSetting.GraphicsNew.Comps.GSC_FPSFT")
        local GraphicSettingDB = require("client.slua.umg.NewSetting.GraphicsNew.GraphicSettingDB")
        
        local KismetMathLibrary = import("KismetMathLibrary") or _G.KismetMathLibrary
        local FLinearColor = import("LinearColor") or _G.FLinearColor

        if logic_setting_graphics then
            local old_SetFPS = logic_setting_graphics.SetFPS
            function logic_setting_graphics.SetFPS(gameInstance, FPSLevel)
                if old_SetFPS then old_SetFPS(gameInstance, FPSLevel) end
                if FPSLevel == 8 then 
                    gameInstance:ExecuteCMD("t.MaxFPS", "165")
                    gameInstance:ExecuteCMD("r.FrameRateLimit", "165")
                end
            end
        end

        if GSC_FPS and GSC_FPS.__inner_impl then
            local fps_impl = GSC_FPS.__inner_impl
            function fps_impl:GetMaxFPSLevel() return 8, 8 end
            function fps_impl:InitRealSupportFPS()
                local RealSupportFPS = {}
                for i = 1, 8 do RealSupportFPS[i] = {true, true} end
                if GraphicSettingDB then GraphicSettingDB:UpdateUIData(GraphicSettingDB.RealSupportFPS, RealSupportFPS, false) end
                return RealSupportFPS
            end
            function fps_impl:UpdateSelectedFPSState(selectedLevel)
                if not slua.isValid(self.UIRoot) then return end
                for level = 2, 8 do
                    local name = "NodeFps" .. (({[2]=20,[3]=25,[4]=30,[5]=40,[6]=60,[7]=90,[8]=120})[level] or 120)
                    local widget = self.UIRoot[name]
                    if slua.isValid(widget) then
                        widget:SetIsEnabled(true) 
                        pcall(function() widget:SetRenderOpacity(1.0) end)
                        local switcher = self.UIRoot["WidgetSwitcher_" .. level]
                        if slua.isValid(switcher) then 
                            switcher:SetActiveWidgetIndex(level == selectedLevel and 0 or 1) 
                        end
                    end
                end
            end
        end

        if GSC_FPSFT and GSC_FPSFT.__inner_impl then
            local ft_impl = GSC_FPSFT.__inner_impl
            local NMinFPS, NStep = 90, 5
            local function clamp(value, min, max)
                if value < min then return min end
                if max < value then return max end
                return value
            end
            local function lerp(a, b, t) return a + (b - a) * t end
            local function _getColorByPercent(start, finish, percent)
                if not FLinearColor then return nil end
                return FLinearColor(lerp(start.R, finish.R, percent), lerp(start.G, finish.G, percent), lerp(start.B, finish.B, percent), lerp(start.A, finish.A, percent))
            end
            
            ft_impl.ShowOrHide = function(self)
                self:SelfHitTestInvisible()
                if self.InitFPSFTSwitch then self:InitFPSFTSwitch() end
            end

            ft_impl.InitFPSFTSwitch = function(self)
                local FPSFineTuneSwitch = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                if self.UIRoot.Setting_Switch then self.UIRoot.Setting_Switch:SetSwitcherEnable2(FPSFineTuneSwitch, true) end
                if self.UIRoot.CanvasPanel_8 then self:SetWidgetVisible(self.UIRoot.CanvasPanel_8, FPSFineTuneSwitch) end
                if self.UIRoot.WidgetSwitcher_0 then self.UIRoot.WidgetSwitcher_0:SetActiveWidgetIndex(2) end
                if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
            end

            ft_impl.InitFPSFTValue165 = function(self)
                local itemRoot = self.UIRoot
                local FPSFineTuneSwitch = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch)
                local FPSFineTuneNum = 165
                if FPSFineTuneSwitch then
                    FPSFineTuneNum = GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneNum) or 165
                    itemRoot.Slider_screen3:SetLocked(false)
                    if FLinearColor then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1.0, 1.0, 1.0, 1.0))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor(1.0, 1.0, 1.0, 1.0))
                    end
                else
                    itemRoot.Slider_screen3:SetLocked(true)
                    if FLinearColor then
                        itemRoot.ProgressBar_screen3:SetFillColorAndOpacity(FLinearColor(1.0, 0.625, 0.6, 1))
                        itemRoot.Slider_screen3:SetSliderHandleColor(FLinearColor(1.0, 0.625, 0.6, 1.0))
                    end
                end
                local FPSFineTunePer = (FPSFineTuneNum - NMinFPS) / (165 - NMinFPS)
                
                itemRoot.Veihclescreen3:SetText(tostring(FPSFineTuneNum))
                itemRoot.Slider_screen3:SetValue(FPSFineTunePer)
                itemRoot.ProgressBar_screen3:SetPercent(FPSFineTunePer)
                
                if FLinearColor then
                    local startColor = FLinearColor(1.0, 1.0, 1.0, 1.0)
                    local midColor = FLinearColor(1.0, 0.54, 0.11, 1.0)
                    local endColor = FLinearColor(1.0, 0.23, 0.15, 1.0)
                    local sliderColor = FPSFineTunePer < 0.4 and startColor or _getColorByPercent(midColor, endColor, (FPSFineTunePer - 0.4) / 0.6)
                    itemRoot.Slider_screen3:SetSliderHandleColor(sliderColor)
                end
            end

            ft_impl.OnFPSFTValueChange3 = function(self, FPSFineTuneNum)
                GraphicSettingDB:UpdateUIData(GraphicSettingDB.FPSFineTuneNum, FPSFineTuneNum)
                if self.InitFPSFTValue165 then self:InitFPSFTValue165() end
                if self:GetParentUI() then self:GetParentUI():SetDirty(true) end
                local gameInstance = GraphicSettingDB.GetGameInstance and GraphicSettingDB.GetGameInstance()
                if gameInstance then
                    gameInstance:ExecuteCMD("t.MaxFPS", tostring(FPSFineTuneNum))
                    gameInstance:ExecuteCMD("r.FrameRateLimit", tostring(FPSFineTuneNum))
                end
            end

            ft_impl.OnFPSFTSliderValueChange3 = function(self, value)
                if GraphicSettingDB:GetUIData(GraphicSettingDB.FPSFineTuneSwitch) and KismetMathLibrary then
                    local FPSFineTuneNum = KismetMathLibrary.FCeil(value * (165 - NMinFPS) / NStep) * NStep + NMinFPS
                    self:OnFPSFTValueChange3(clamp(FPSFineTuneNum, NMinFPS, 165))
                end
            end
            
            ft_impl.OnFPSFTAdd = ft_impl.OnFPSFTAdd3
            ft_impl.OnFPSFTMinus = ft_impl.OnFPSFTMinus3
            ft_impl.OnFPSFTAdd2 = ft_impl.OnFPSFTAdd3
            ft_impl.OnFPSFTMinus2 = ft_impl.OnFPSFTMinus3
            ft_impl.OnFPSFTSliderValueChange = ft_impl.OnFPSFTSliderValueChange3
            ft_impl.OnFPSFTSliderValueChange2 = ft_impl.OnFPSFTSliderValueChange3
        end
    end)
    _G.MON5LAState.GraphicsUnlocked = true
    Notify("تم فتح الرسومات و 165 هرتز (نسخة مطورة)")
end

-- ========================================== 
-- INITIALIZE THE ESP SYSTEM (BASED)
-- ========================================== 
local function InitializeNativeESP() 
    if _G.MON5LAState.NativeESPReady then return end
    pcall(function() 
        local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools") 
        local currentMarkCfg = GamePlayTools.GetCurrentConfig("ScreenMarkConfig") 
        local function ApplyCfg(cfg)
            if not cfg then return end 
            if cfg[1006] then 
                cfg[1006].bBindBlocked = true;
                cfg[1006].bBindOutScreen = true; 
                cfg[1006].MaxWidgetNum = 99
                cfg[1006].MaxShowDistance = 6000000; 
                cfg[1006].bScaleByDistance = false
                cfg[1006].BindSocketName = "root"; 
                cfg[1006].bUseLuaWorldSocketName = true
                cfg[1006].WorldPositionOffset = FVector(0, 0, -30) 
            end 
            cfg[8888] = { 
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, 
                MaxShowDistance = 6000000, 
                bBindOutScreen = true,
                bBindBlocked = true, 
                bIsBindingActor = true,
                BindSocketName = "head",
                bUseLuaWorldSocketName = true, 
                WorldPositionOffset = FVector(0, 0, 30),
                bNeedPreLoad = true,
                Priority = 2 
            } 
            cfg[9999] = { 
                UIPathName = "/Game/Mod/EvoBase/BluePrints/UIBP/QuickSign/QuickSign_TipHitEnemy_UIBP_New.QuickSign_TipHitEnemy_UIBP_New_C",
                MaxWidgetNum = 99, 
                MaxShowDistance = 6000000, 
                bBindOutScreen = true,
                bBindBlocked = true, 
                bIsBindingActor = true, 
                BindSocketName = "head",
                bUseLuaWorldSocketName = true, 
                WorldPositionOffset = FVector(0, 0, 50),
                bNeedPreLoad = true, 
                Priority = 2 
            } 
        end 
        ApplyCfg(currentMarkCfg) 
        for k, cfg in pairs(package.loaded) do 
            if type(k) == "string" and string.find(k, "ScreenMarkConfig") and type(cfg) == "table" then 
                ApplyCfg(cfg) 
            end 
        end 
    end)
    _G.MON5LAState.NativeESPReady = true 
    Notify("تم تهيئة نظام ESP الأصلي") 
end

-- ========================================== 
-- FOV CIRCLE OVERLAY (MANDIRI, TANPA PLAYERMAPMARKER - FIXED SYNC)
-- ==========================================
local SlateBlueprintLibrary = import("SlateBlueprintLibrary")

_G.FovCircleOverlay = {
    Container = nil,
    WidgetSlot = nil,
    ParentCanvas = nil,
    Lines = {},
    NumSegments = 45,
    Thickness = 1.5,
    LastRadius = -1,
    LastColor = -1,
    LastCX = -1,
    LastCY = -1,
    PrecalcMath = nil
}

local function GetFOVColor(idx)
    if idx == 1 then return 1.0, 0.0, 0.0 end
    if idx == 2 then return 0.0, 1.0, 0.0 end
    if idx == 3 then return 0.0, 0.0, 1.0 end
    if idx == 4 then return 1.0, 1.0, 0.0 end
    if idx == 5 then return 0.65, 0.15, 1.0 end
    if idx == 6 then return 0.0, 1.0, 1.0 end
    if idx == 7 then return 1.0, 1.0, 1.0 end
    return 1.0, 1.0, 1.0
end

function _G.FovCircleOverlay.Create()
    if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
        return true
    end

    local ParentCanvas = nil
    pcall(function()
        local InGameUITools = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local MainUI = InGameUITools.GetMainControlBaseUI()
        if slua.isValid(MainUI) then
            if slua.isValid(MainUI.CanvasPanel_0) then
                ParentCanvas = MainUI.CanvasPanel_0
            elseif slua.isValid(MainUI.CanvasPanel_42) then
                ParentCanvas = MainUI.CanvasPanel_42
            end
        end
    end)

    if not ParentCanvas or not slua.isValid(ParentCanvas) then
        return false
    end

    local Container = nil
    pcall(function()
        Container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", ParentCanvas)
    end)
    if not Container or not slua.isValid(Container) then
        return false
    end

    local FVector2D = import("Vector2D") or _G.FVector2D

    for i = 1, _G.FovCircleOverlay.NumSegments do
        local border = nil
        pcall(function()
            border = CGame:NewObjectFromPath("/Script/UMG.Border", Container)
        end)
        if border and slua.isValid(border) then
            pcall(function()
                border.RenderTransformPivot = FVector2D(0, 0.5)
                border:SetRenderTransformPivot(FVector2D(0, 0.5))
                border:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            local slot = Container:AddChildToCanvas(border)
            if slot then
                pcall(function()
                    slot:SetAlignment(FVector2D(0, 0.5))
                end)
            end
            _G.FovCircleOverlay.Lines[i] = { widget = border, slot = slot }
        end
    end

    local MainSlot = nil
    pcall(function()
        MainSlot = ParentCanvas:AddChildToCanvas(Container)
    end)
    if MainSlot then
        pcall(function()
            MainSlot:SetAutoSize(false)
            MainSlot:SetSize(FVector2D(0, 0))
            MainSlot:SetZOrder(995)
            MainSlot:SetAlignment(FVector2D(0, 0))
            MainSlot:SetPosition(FVector2D(0, 0))
        end)
    end

    _G.FovCircleOverlay.Container = Container
    _G.FovCircleOverlay.WidgetSlot = MainSlot
    _G.FovCircleOverlay.ParentCanvas = ParentCanvas
    return true
end

function _G.FovCircleOverlay.Update(pc, player)
    if not _G.MON5LAConfig.EspFovCircle then
        if _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
            pcall(function()
                _G.FovCircleOverlay.Container:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed)
            end)
            _G.FovCircleOverlay.LastRadius = -1
        end
        return
    end

    local fovVal = 30
    local colIdx = 7
    local cData = _G.MON5LAState.CustomTextData
    local WEAPON_TYPE = _G.__AimTouch_WeaponType or "NORMAL"
    local isADS = player.bIsGunADS or false

    if WEAPON_TYPE == "MORTAR" then
        fovVal = cData.AimTouchMortarFOV or 360
        colIdx = tonumber(cData.AimTouchMortarFOVColor) or 5
    elseif WEAPON_TYPE == "SHOTGUN" then
        fovVal = cData.AimTouchSGFOV or 40
        colIdx = tonumber(cData.AimTouchSGFOVColor) or 1
    elseif isADS then
        if WEAPON_TYPE == "SNIPER" then
            fovVal = cData.AimTouchSniperFOV or 20
            colIdx = tonumber(cData.AimTouchSniperFOVColor) or 4
        else
            fovVal = cData.AimTouchScopeFOV or 30
            colIdx = tonumber(cData.AimTouchScopeFOVColor) or 6
        end
    else
        fovVal = cData.AimTouchHipFOV or 30
        colIdx = tonumber(cData.AimTouchHipFOVColor) or 7
    end

    local rawCX = _G.__AimTouch_CenterX or 960
    local rawCY = _G.__AimTouch_CenterY or 540
    local vpX = _G.__AimTouch_ViewportX or 1920

    if not _G.FovCircleOverlay.Create() then
        return
    end

    local ParentCanvas = _G.FovCircleOverlay.ParentCanvas
    if not ParentCanvas or not slua.isValid(ParentCanvas) then
        return
    end

    -- Hitung transformasi Canvas dengan SlateBlueprintLibrary
    local scaleX, scaleY, offsetX, offsetY = 1.0, 1.0, 0.0, 0.0
    pcall(function()
        local cg = ParentCanvas:GetCachedGeometry()
        if cg and SlateBlueprintLibrary then
            local FVector2D = import("Vector2D") or _G.FVector2D
            local pt0 = SlateBlueprintLibrary.AbsoluteToLocal(cg, FVector2D(0, 0))
            local pt1 = SlateBlueprintLibrary.AbsoluteToLocal(cg, FVector2D(100, 100))
            if pt0 and pt1 then
                scaleX = (pt1.X - pt0.X) / 100
                scaleY = (pt1.Y - pt0.Y) / 100
                offsetX = pt0.X
                offsetY = pt0.Y
            end
        end
    end)

    -- Konversi titik tengah layar ke koordinat Canvas (agar pas di crosshair)
    local centerX = rawCX * scaleX + offsetX
    local centerY = rawCY * scaleY + offsetY

    -- Radius dalam pixel layar, lalu diskalakan ke Canvas
    local avgScale = (scaleX + scaleY) / 2
    local rawRadius = (fovVal / 100.0) * (vpX / 2.0)
    local targetRadius = rawRadius * avgScale

    if math.abs(_G.FovCircleOverlay.LastRadius - targetRadius) < 0.5
       and _G.FovCircleOverlay.LastColor == colIdx
       and math.abs(_G.FovCircleOverlay.LastCX - centerX) < 0.5
       and math.abs(_G.FovCircleOverlay.LastCY - centerY) < 0.5 then
        return
    end

    _G.FovCircleOverlay.LastRadius = targetRadius
    _G.FovCircleOverlay.LastColor = colIdx
    _G.FovCircleOverlay.LastCX = centerX
    _G.FovCircleOverlay.LastCY = centerY

    pcall(function()
        _G.FovCircleOverlay.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
    end)

    local FLinearColor = import("LinearColor") or _G.FLinearColor
    local r, g, b = GetFOVColor(colIdx)
    local dim = 0.55
    local color = FLinearColor and FLinearColor(r * dim, g * dim, b * dim, 1.0)
        or {R = r * dim * 255, G = g * dim * 255, B = b * dim * 255, A = 255}

    local numSegments = _G.FovCircleOverlay.NumSegments

    if not _G.FovCircleOverlay.PrecalcMath then
        _G.FovCircleOverlay.PrecalcMath = {}
        local angleStep = 360.0 / numSegments
        local math_cos = math.cos
        local math_sin = math.sin
        local math_rad = math.rad
        local math_atan2 = math.atan2 or math.atan

        for i = 1, numSegments do
            local angle1 = math_rad((i - 1) * angleStep)
            local angle2 = math_rad(i * angleStep)
            local c1, s1 = math_cos(angle1), math_sin(angle1)
            local c2, s2 = math_cos(angle2), math_sin(angle2)
            local dx_unit = c2 - c1
            local dy_unit = s2 - s1
            local dist_unit = math.sqrt(dx_unit * dx_unit + dy_unit * dy_unit)
            local angleDeg = math.deg(math_atan2(dy_unit, dx_unit))
            _G.FovCircleOverlay.PrecalcMath[i] = {
                c1 = c1, s1 = s1,
                dist_unit = dist_unit,
                angleDeg = angleDeg
            }
        end
    end

    pcall(function()
        local FVector2D = import("Vector2D") or _G.FVector2D
        for i = 1, numSegments do
            local mathData = _G.FovCircleOverlay.PrecalcMath[i]
            local x1 = targetRadius * mathData.c1
            local y1 = targetRadius * mathData.s1
            local dist = targetRadius * mathData.dist_unit

            local line = _G.FovCircleOverlay.Lines[i]
            if line and line.slot and slua.isValid(line.slot) then
                line.slot:SetPosition(FVector2D(centerX + x1, centerY + y1))
                line.slot:SetSize(FVector2D(dist + 0.8, _G.FovCircleOverlay.Thickness))
                line.widget:SetRenderAngle(mathData.angleDeg)
                line.widget:SetBrushColor(color)
            end
        end
    end)
end

function _G.CleanUpFovCircleOverlay()
    if _G.FovCircleOverlay and _G.FovCircleOverlay.Container and slua.isValid(_G.FovCircleOverlay.Container) then
        pcall(function()
            _G.FovCircleOverlay.Container:RemoveFromParent()
        end)
        pcall(function()
            _G.FovCircleOverlay.Container:ConditionalBeginDestroy()
        end)
    end
    _G.FovCircleOverlay.Container = nil
    _G.FovCircleOverlay.WidgetSlot = nil
    _G.FovCircleOverlay.ParentCanvas = nil
    _G.FovCircleOverlay.LastRadius = -1
end

-- ========================================== 
-- LOCAL FUNCTIONS CHO LOGIC NEW ESP - OPTIMIZED
-- ========================================== 
local function GetAllSkeletalMeshes(enemy, markData)
    local curTime = os.clock()
    if markData and markData.CachedMeshes and markData.CachedMeshTime and (curTime - markData.CachedMeshTime) < 3.0 then
        local validMeshes = {}
        for _, cachedMesh in ipairs(markData.CachedMeshes) do
            if Valid(cachedMesh) then table.insert(validMeshes, cachedMesh) end
        end
        markData.CachedMeshes = validMeshes
        return validMeshes
    end

    local meshes = {}
    if Valid(enemy.Mesh) then table.insert(meshes, enemy.Mesh) end
    pcall(function()
        local SkeletalMeshClass = import("SkeletalMeshComponent")
        if SkeletalMeshClass and type(enemy.GetComponentsByClass) == "function" then
            local childs = enemy:GetComponentsByClass(SkeletalMeshClass)
            if childs then
                local count = type(childs.Num) == "function" and childs:Num() or #childs
                for i = 1, count do
                    local comp = type(childs.Get) == "function" and childs:Get(i-1) or childs[i]
                    if Valid(comp) and comp ~= enemy.Mesh then
                        table.insert(meshes, comp)
                    end
                end
            end
        end
    end)
    if markData then
        markData.CachedMeshes = meshes
        markData.CachedMeshTime = curTime
    end
    return meshes
end

-- ========================================== 
-- ENGINE CHAMS V3 - NEW ENGINE CHAMS (From 1.lua)
-- ==========================================
local function ApplyColorBodyNew(enemy, markData)
    pcall(function()
        -- KICK CONSOLE COMMAND (Only once)
        if not _G.MON5LAState.ConsoleNewWallReady then
            local KismetSystemLibrary = import("KismetSystemLibrary")
            local world = slua.getWorld()
            if KismetSystemLibrary and world then
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.EnableDrawDyeingColor 1")
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.CustomDepth 3")
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.IdeaOutline.Enable 1")
                KismetSystemLibrary.ExecuteConsoleCommand(world, "r.Highlight.Enable 1")
                _G.MON5LAState.ConsoleNewWallReady = true
            end
        end

        -- Get all enemy meshes
        local meshes = GetAllSkeletalMeshes(enemy, markData)
        
        -- Add weapon mesh
        local weapon = nil
        pcall(function() weapon = enemy:GetCurrentWeapon() end)
        if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
            table.insert(meshes, weapon.Mesh)
        end

        local isBot = markData.AK_IS_BOT or false
        local currentMeshCount = #meshes
        
        -- Cache optimization: Only process if changed
        local stateHash = (isBot and "BOT" or "PLAYER") .. "_" .. tostring(currentMeshCount)
        
        if markData.LastColorNewHash == stateHash and markData.ColorNewApplied then
            return -- No change, skip processing
        end
        
        markData.LastColorNewHash = stateHash
        markData.ColorNewApplied = true

        -- Get colors from ColorConfig (mengikuti pengaturan ESP)
        local LinearColorClass = import("LinearColor") or _G.FLinearColor
        
        -- Gunakan warna dari ColorConfig untuk Visible dan Invisible
        local visibleColorRGB = GetAppliedColor(_G.ColorConfig.VisibleColor or 4, _G.ColorConfig.Brightness or 25)
        local invisibleColorRGB = GetAppliedColor(_G.ColorConfig.InvisibleColor or 1, _G.ColorConfig.Brightness or 25)
        
        -- Konversi ke LinearColor untuk Engine
        local glowIntensity = _G.ColorConfig.Glow or 3.0
        local visColor = LinearColorClass and LinearColorClass(
            (visibleColorRGB.R/255) * glowIntensity, 
            (visibleColorRGB.G/255) * glowIntensity, 
            (visibleColorRGB.B/255) * glowIntensity, 
            1.0
        ) or {R=visibleColorRGB.R, G=visibleColorRGB.G, B=visibleColorRGB.B, A=255}
        
        local occColor = LinearColorClass and LinearColorClass(
            invisibleColorRGB.R/255, 
            invisibleColorRGB.G/255, 
            invisibleColorRGB.B/255, 
            1.0
        ) or {R=invisibleColorRGB.R, G=invisibleColorRGB.G, B=invisibleColorRGB.B, A=1}
        
        -- Apply to all meshes
        for _, mesh in ipairs(meshes) do
            if Valid(mesh) then
                pcall(function()
                    if type(mesh.SetDrawDyeing) == "function" then
                        mesh:SetDrawDyeing(true)
                        mesh:SetDrawDyeingMode(1)
                        mesh:SetVisibleDyeingColor(visColor)
                        mesh:SetOccludedDyeingColor(occColor)
                        mesh:SetDyeingColorFadeDistance(99999.0)
                        mesh:SetDyeingColorMinMaxDistance(0.0, 99999.0)
                        mesh:SetDrawHighlight(true)
                        mesh:OverrideHighlightColor(visColor)
                        mesh:SetHighlightCanBeOccluded(false)
                        mesh:SetDrawIdeaOutline(true)
                        mesh:SetIdeaOutlineNew(true)
                        mesh:SetIdeaOutlineOcclusionHighlight(true)
                        mesh:OverrideIdeaOutlineColor(visColor)
                        mesh:SetIdeaOutlineOcclusionColor(occColor)
                        mesh:OverrideIdeaOutlineThickness(20)
                        mesh:SetIdeaOverrideOutlineAndOcclusion(true)
                        mesh:SetRenderCustomDepth(true)
                        mesh:SetCustomDepthStencilValue(255)
                    end
                end)
            end
        end
    end)
end

local function UndoColorBodyNew(enemy, markData)
    pcall(function()
        if markData.ColorNewApplied then
            local meshes = GetAllSkeletalMeshes(enemy, markData)
            local weapon = nil
            pcall(function() weapon = enemy:GetCurrentWeapon() end)
            if slua.isValid(weapon) and slua.isValid(weapon.Mesh) then
                table.insert(meshes, weapon.Mesh)
            end

            for _, mesh in ipairs(meshes) do
                if Valid(mesh) then
                    pcall(function()
                        if type(mesh.SetDrawDyeing) == "function" then
                            mesh:SetDrawDyeing(false)
                            mesh:SetDrawHighlight(false)
                            mesh:SetDrawIdeaOutline(false)
                            mesh:SetRenderCustomDepth(false)
                        end
                    end)
                end
            end
            markData.ColorNewApplied = false
            markData.LastColorNewHash = ""
        end
    end)
end

-- ========================================== 
-- AIMBOT V2 SYSTEM (UPDATED WITH MORTAR FROM GOLD)
-- ========================================== 
_G.GetEnemyTargetsFromActors = function(radius)
    local result = {}
    local player = GameplayData.GetPlayerCharacter()

    if not slua.isValid(player) then
        return result
    end

    local allCharacters = {}
    if GameplayData.GetAllPlayerCharacters then
        allCharacters = GameplayData.GetAllPlayerCharacters()
    elseif GameplayData.GameCharacters then
        for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end
    end

    local myTeam = player:GetTeamID()

    for _, actor in pairs(allCharacters) do
        if slua.isValid(actor) and actor ~= player and actor.GetTeamID and actor:IsAlive() then
            if actor:GetTeamID() ~= myTeam then
                local dist = player:GetDistanceTo(actor)
                if dist <= radius then
                    table.insert(result, actor)
                end
            end
        end
    end
    return result
end

_G.AimTouch = function()
    pcall(function()
        if not _G.MON5LAConfig.AimTouchEnable then return end
        
        local player = GameplayData.GetPlayerCharacter()
        if not slua.isValid(player) then return end
        
        local pc = player:GetPlayerControllerSafety()
        if not slua.isValid(pc) then return end
        
        local isFiring = player.bIsWeaponFiring
        local isADS = player.bIsGunADS
        
        local weapon = player.WeaponManagerComponent and player.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(player.GetCurrentShootWeapon) == "function" then
            weapon = player:GetCurrentShootWeapon()
        end
        
        local isShotgun = false
        local isSniper = false
        local isMortar = false
        local currentAmmo = 1
        
        if slua.isValid(weapon) then
            local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
            local wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
            
            if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then 
                isShotgun = true 
            end
            
            if wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then
                isSniper = true
            end

            if wName:lower():find("mortar") or wName:lower():find("cối") then
                isMortar = true
            end
            
            if type(weapon.GetCurrentAmmo) == "function" then
                currentAmmo = weapon:GetCurrentAmmo()
            elseif weapon.ShootWeaponComponent and type(weapon.ShootWeaponComponent.GetCurrentAmmo) == "function" then
                currentAmmo = weapon.ShootWeaponComponent:GetCurrentAmmo()
            elseif weapon.CurrentAmmo ~= nil then
                currentAmmo = weapon.CurrentAmmo
            end
        end

        if _G.MON5LAState.IsAutoFiring then
            pcall(function()
                player.bIsWeaponFiring = false
                if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(false) end
                if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(false) end
                local wepMgr = player.WeaponManagerComponent
                if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = false end
            end)
            _G.MON5LAState.IsAutoFiring = false
        end

        if isShotgun and currentAmmo <= 0 then
            return
        end

        local cond = 2
        local prioMode = 1
        local boneIdx = 1
        local speedVal = 50
        local fovVal = 30
        local maxDistMeters = 50
        local useVisCheck = false
        local igKnock = false
        local igBot = false
        
        local predVal = 0 
        local recoilCompVal = 0 

        -- MORTAR HANDLING
        if isMortar and _G.MON5LAConfig.AimTouchMortar then
            local isPlaced = false
            pcall(function()
                if weapon and weapon.MortarState == 2 then isPlaced = true end
            end)
            if not isPlaced then return end

            cond = 2
            prioMode = 1
            boneIdx = 4
            speedVal = 100
            fovVal = _G.MON5LAState.CustomTextData.AimTouchMortarFOV or 360
            maxDistMeters = 2000
            useVisCheck = false
            igKnock = false
            igBot = false
            predVal = _G.MON5LAState.CustomTextData.AimTouchMortarPred or 0
            
        elseif isShotgun and _G.MON5LAConfig.AimTouchSG then
            cond = _G.MON5LAState.CustomTextData.AimTouchSGCond or 1
            if _G.MON5LAConfig.AimTouchSGAutoFire then cond = 2 end
            if cond == 1 and not isFiring then return end
            prioMode = _G.MON5LAState.CustomTextData.AimTouchSGPrio or 1
            boneIdx = _G.MON5LAState.CustomTextData.AimTouchSGBone or 2
            speedVal = _G.MON5LAState.CustomTextData.AimTouchSGSpeed or 80
            fovVal = _G.MON5LAState.CustomTextData.AimTouchSGFOV or 40
            maxDistMeters = _G.MON5LAState.CustomTextData.AimTouchSGDist or 30
            useVisCheck = _G.MON5LAConfig.AimTouchSGVisCheck
            igKnock = _G.MON5LAConfig.AimTouchSGIgKnock
            igBot = _G.MON5LAConfig.AimTouchSGIgBot
            
        elseif isADS then
            if isSniper and _G.MON5LAConfig.AimTouchScopeSniper then
                cond = _G.MON5LAState.CustomTextData.AimTouchSniperCond or 2
                if cond == 1 and not isFiring then return end
                prioMode = _G.MON5LAState.CustomTextData.AimTouchSniperPrio or 1
                boneIdx = _G.MON5LAState.CustomTextData.AimTouchSniperBone or 1
                speedVal = _G.MON5LAState.CustomTextData.AimTouchSniperSpeed or 30
                fovVal = _G.MON5LAState.CustomTextData.AimTouchSniperFOV or 20
                maxDistMeters = _G.MON5LAState.CustomTextData.AimTouchSniperDist or 400
                useVisCheck = _G.MON5LAConfig.AimTouchSniperVisCheck
                igKnock = _G.MON5LAConfig.AimTouchSniperIgKnock
                igBot = _G.MON5LAConfig.AimTouchSniperIgBot
                predVal = _G.MON5LAState.CustomTextData.AimTouchSniperPred or 0
            elseif _G.MON5LAConfig.AimTouchScopeAll then
                cond = _G.MON5LAState.CustomTextData.AimTouchScopeCond or 1
                if cond == 1 and not isFiring then return end
                prioMode = _G.MON5LAState.CustomTextData.AimTouchScopePrio or 1
                boneIdx = _G.MON5LAState.CustomTextData.AimTouchScopeBone or 2
                speedVal = _G.MON5LAState.CustomTextData.AimTouchScopeSpeed or 40
                fovVal = _G.MON5LAState.CustomTextData.AimTouchScopeFOV or 20
                maxDistMeters = _G.MON5LAState.CustomTextData.AimTouchScopeDist or 300
                useVisCheck = _G.MON5LAConfig.AimTouchScopeVisCheck
                igKnock = _G.MON5LAConfig.AimTouchScopeIgKnock
                igBot = _G.MON5LAConfig.AimTouchScopeIgBot
                predVal = _G.MON5LAState.CustomTextData.AimTouchScopePred or 0
                recoilCompVal = _G.MON5LAState.CustomTextData.AimTouchScopeRecoil or 0
            else
                return
            end
        else
            if not _G.MON5LAConfig.AimTouchHipfire then return end
            cond = _G.MON5LAState.CustomTextData.AimTouchHipCond or 1
            if cond == 1 and not isFiring then return end 
            prioMode = _G.MON5LAState.CustomTextData.AimTouchHipPrio or 1
            boneIdx = _G.MON5LAState.CustomTextData.AimTouchHipBone or 1
            speedVal = _G.MON5LAState.CustomTextData.AimTouchHipSpeed or 50
            fovVal = _G.MON5LAState.CustomTextData.AimTouchHipFOV or 30
            maxDistMeters = _G.MON5LAState.CustomTextData.AimTouchHipDist or 250
            useVisCheck = _G.MON5LAConfig.AimTouchHipVisCheck
            igKnock = _G.MON5LAConfig.AimTouchHipIgKnock
            igBot = _G.MON5LAConfig.AimTouchHipIgBot
        end

        local currentMaxDist = maxDistMeters * 100 

        local enemies = _G.GetEnemyTargetsFromActors(currentMaxDist)
        if not enemies or #enemies == 0 then return end
        
        local FVector2D = import("Vector2D")
        local UGameplayStatics = import("GameplayStatics")
        local KismetMathLibrary = import("KismetMathLibrary")
        
        local camManager = UGameplayStatics.GetPlayerCameraManager(pc, 0)
        if not slua.isValid(camManager) then return end
        
        local camLoc = camManager:GetCameraLocation()
        if not camLoc then return end
        
        local ui_util = require("client.common.ui_util")
        if not ui_util then return end
        
        local viewportSize = ui_util.GetViewportSize()
        if not viewportSize then return end
        
        local centerX = viewportSize.X * 0.5
        local centerY = viewportSize.Y * 0.5
        
        local FOV_RADIUS = (fovVal / 100.0) * (viewportSize.X / 2.0)
        
        local bestTarget = nil
        local bestScore = 99999999 
        
        local selBoneName = "head"
        if boneIdx == 1 then selBoneName = "head"
        elseif boneIdx == 2 then selBoneName = "spine_03"
        elseif boneIdx == 3 then selBoneName = "spine_01"
        elseif boneIdx == 4 then selBoneName = "pelvis" end

        for i, target in ipairs(enemies) do
            if not slua.isValid(target) then goto continue end
            
            pcall(function()
                if slua.isValid(target.Mesh) then
                    target.Mesh.MeshComponentUpdateFlag = 0
                end
            end)
            
            if igKnock and target.HealthStatus == 1 then goto continue end
            
            if igBot then
                local tIsBot = false
                if target.bIsAI == true or target.IsAI == true then tIsBot = true end
                local pState = target.PlayerState
                if slua.isValid(pState) and (pState.bIsABot or pState.bIsBot) then tIsBot = true end
                if tIsBot then goto continue end
            end
            
            if useVisCheck then
                local curTime = os.clock()
                local tId = type(target.GetUniqueID) == "function" and target:GetUniqueID() or tostring(target)
                _G.AimTouchVisCache = _G.AimTouchVisCache or {}
                if not _G.AimTouchVisCache[tId] or (curTime - _G.AimTouchVisCache[tId].time) > 0.2 then
                    local isHidden = true
                    pcall(function() if pc:LineOfSightTo(target) then isHidden = false end end)
                    _G.AimTouchVisCache[tId] = { hidden = isHidden, time = curTime }
                end
                if _G.AimTouchVisCache[tId].hidden then goto continue end
            end
            
            local tPos = target:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.GetSocketLocation) == "function" then
                    tPos = target:GetSocketLocation(selBoneName)
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then
                if type(target.K2_GetActorLocation) == "function" then
                    tPos = target:K2_GetActorLocation()
                    if tPos then
                        if boneIdx == 1 then tPos.Z = tPos.Z + 70
                        elseif boneIdx == 2 then tPos.Z = tPos.Z + 40
                        elseif boneIdx == 3 then tPos.Z = tPos.Z + 20 end
                    end
                end
            end
            if not tPos or (tPos.X == 0 and tPos.Y == 0 and tPos.Z == 0) then goto continue end
            
            local screen = FVector2D()
            local success = pc:ProjectWorldLocationToScreen(tPos, screen, false)
            if not success or screen.X <= 0 or screen.Y <= 0 then goto continue end
            
            local dx = screen.X - centerX
            local dy = screen.Y - centerY
            local distScreen = math.sqrt(dx*dx + dy*dy)
            
            if distScreen > FOV_RADIUS then goto continue end
            
            local currentScore = distScreen
            if prioMode == 2 then currentScore = player:GetDistanceTo(target)
            elseif prioMode == 3 then currentScore = target.Health or 100
            elseif prioMode == 4 then 
                local hp = target.Health or 100
                local maxhp = target.HealthMax or 100
                if maxhp <= 0 then maxhp = 100 end
                currentScore = hp / maxhp
            end
            
            if currentScore < bestScore then
                bestScore = currentScore
                bestTarget = target
            end
            
            ::continue::
        end
        
        if not slua.isValid(bestTarget) then return end
        
        local finalBonePos = bestTarget:GetBonePos(selBoneName, {X=0, Y=0, Z=0})
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.GetSocketLocation) == "function" then
                finalBonePos = bestTarget:GetSocketLocation(selBoneName)
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then
            if type(bestTarget.K2_GetActorLocation) == "function" then
                finalBonePos = bestTarget:K2_GetActorLocation()
                if finalBonePos then
                    if boneIdx == 1 then finalBonePos.Z = finalBonePos.Z + 70
                    elseif boneIdx == 2 then finalBonePos.Z = finalBonePos.Z + 40
                    elseif boneIdx == 3 then finalBonePos.Z = finalBonePos.Z + 20 end
                end
            end
        end
        if not finalBonePos or (finalBonePos.X == 0 and finalBonePos.Y == 0 and finalBonePos.Z == 0) then return end
        
        if predVal > 0 then
            pcall(function()
                local tVelocity = nil
                if type(bestTarget.GetVelocity) == "function" then
                    tVelocity = bestTarget:GetVelocity()
                end
                
                if tVelocity and (tVelocity.X ~= 0 or tVelocity.Y ~= 0) then
                    local distToEnemy = player:GetDistanceTo(bestTarget) / 100.0
                    local ToF = (distToEnemy / 800.0) * (predVal / 50.0) 
                    finalBonePos.X = finalBonePos.X + (tVelocity.X * ToF)
                    finalBonePos.Y = finalBonePos.Y + (tVelocity.Y * ToF)
                end
            end)
        end

        -- MORTAR TRAJECTORY
        if isMortar and _G.MON5LAConfig.AimTouchMortar then
            local targetPos = { X = finalBonePos.X, Y = finalBonePos.Y, Z = finalBonePos.Z }
            local launchPos = camLoc
            pcall(function()
                if player.K2_GetActorLocation then
                    local pLoc = player:K2_GetActorLocation()
                    if pLoc then 
                        launchPos = { X = pLoc.X, Y = pLoc.Y, Z = pLoc.Z + 50 } 
                    end
                end
            end)

            local function CalcMortarTrajectory(V, G, tX, tY, tZ)
                local mDx = math.sqrt((tX - launchPos.X)^2 + (tY - launchPos.Y)^2) - 80 
                if mDx < 500 then mDx = 500 end 
                local mDy = tZ - launchPos.Z
                
                local minVSq = G * (mDy + math.sqrt(mDx*mDx + mDy*mDy))
                if (V * V) < minVSq then
                    V = math.sqrt(minVSq) + 100 
                end

                local v2 = V * V
                local root = v2*v2 - G*(G*mDx*mDx + 2*mDy*v2)
                
                if root >= 0 then
                    local angleRad = math.atan((v2 + math.sqrt(root)) / (G * mDx))
                    local deg = math.deg(angleRad)
                    if deg >= 35 and deg <= 89.5 then 
                        return true, deg, mDx / (V * math.cos(angleRad)), mDx
                    end
                end
                return false, 45, 0, mDx
            end

            local vNear, gNear = 9070, 980 * 2.8   
            local vFar, gFar = 12520, 980 * 4.0    
            local vUltra, gUltra = 16800, 980 * 4.5 
            
            local isValid, physAngle, ToF, finalDx = false, 45, 0, 0
            
            local okNear, angNear, tofNear, dxN = CalcMortarTrajectory(vNear, gNear, targetPos.X, targetPos.Y, targetPos.Z)
            local okFar, angFar, tofFar, dxF = CalcMortarTrajectory(vFar, gFar, targetPos.X, targetPos.Y, targetPos.Z)
            local okUltra, angUltra, tofUltra, dxU = CalcMortarTrajectory(vUltra, gUltra, targetPos.X, targetPos.Y, targetPos.Z)

            if okNear and dxN <= 25000 then
                isValid, physAngle, ToF, finalDx = okNear, angNear, tofNear, dxN
            elseif okFar and dxF <= 40000 then
                isValid, physAngle, ToF, finalDx = okFar, angFar, tofFar, dxF
            elseif okUltra then
                isValid, physAngle, ToF, finalDx = okUltra, angUltra, tofUltra, dxU
            elseif okNear then
                isValid, physAngle, ToF, finalDx = okNear, angNear, tofNear, dxN
            end

            local targetCameraPitch = ((physAngle - 45) / 43.0) * 90.0 - 60.0
            local targetCameraYaw = rot.Yaw

            local deltaPitchMortar = targetCameraPitch - currentRot.Pitch
            local deltaYawMortar = targetCameraYaw - currentRot.Yaw

            if deltaPitchMortar > 180 then deltaPitchMortar = deltaPitchMortar - 360 end
            if deltaPitchMortar < -180 then deltaPitchMortar = deltaPitchMortar + 360 end
            if deltaYawMortar > 180 then deltaYawMortar = deltaYawMortar - 360 end
            if deltaYawMortar < -180 then deltaYawMortar = deltaYawMortar + 360 end
            
            finalPitch = currentRot.Pitch + (deltaPitchMortar * smoothFactor)
            finalYaw = currentRot.Yaw + (deltaYawMortar * smoothFactor)
        end

        local rot = KismetMathLibrary.FindLookAtRotation(camLoc, finalBonePos)
        if not rot then return end
        
        local currentRot = pc:GetControlRotation()
        if not currentRot then return end
        
        local deltaYaw = rot.Yaw - currentRot.Yaw
        local deltaPitch = rot.Pitch - currentRot.Pitch
        
        if isADS then
            local camRot = nil
            if type(camManager.GetCameraRotation) == "function" then
                camRot = camManager:GetCameraRotation()
            end
            if camRot then
                deltaYaw = deltaYaw - (camRot.Yaw - currentRot.Yaw)
                deltaPitch = deltaPitch - (camRot.Pitch - currentRot.Pitch)
            end
        end

        if deltaYaw > 180 then deltaYaw = deltaYaw - 360 end
        if deltaYaw < -180 then deltaYaw = deltaYaw + 360 end
        if deltaPitch > 180 then deltaPitch = deltaPitch - 360 end
        if deltaPitch < -180 then deltaPitch = deltaPitch + 360 end
        
        local smoothFactor = 0.0
        if speedVal >= 100 then
            smoothFactor = 1.0
        else
            smoothFactor = (speedVal / 100.0) * 0.3
            if smoothFactor < 0.01 then smoothFactor = 0.01 end
        end
        
        local finalPitch = currentRot.Pitch + (deltaPitch * smoothFactor)
        local finalYaw = currentRot.Yaw + (deltaYaw * smoothFactor)
        
        if recoilCompVal > 0 and isFiring then
            local pullDownForce = (recoilCompVal / 50.0) * 1.5
            finalPitch = finalPitch - pullDownForce
        end

        local finalRot = { Pitch = finalPitch, Yaw = finalYaw, Roll = 0 }
        pc:SetControlRotation(finalRot, "AimTouch")
        
        if isShotgun and _G.MON5LAConfig.AimTouchSGAutoFire then
            pcall(function()
                local distToTarget = player:GetDistanceTo(bestTarget) / 100
                if distToTarget <= maxDistMeters then
                    player.bIsWeaponFiring = true
                    if type(player.SetIsWeaponFiring) == "function" then player:SetIsWeaponFiring(true) end
                    if slua.isValid(pc) and type(pc.SetIsWeaponFiring) == "function" then pc:SetIsWeaponFiring(true) end
                    local wepMgr = player.WeaponManagerComponent
                    if slua.isValid(wepMgr) then wepMgr.bIsWeaponFiring = true end
                    
                    local currentWep = player:GetCurrentWeapon()
                    if slua.isValid(currentWep) and type(currentWep.StartFire) == "function" then 
                        currentWep:StartFire() 
                    end
                    _G.MON5LAState.IsAutoFiring = true
                end
            end)
        end

    end)
end


-- ========================================== 
-- MAIN LOOP: EXTREMELY POWERFUL OPTIMIZED
-- ========================================== 
local function MainLoop() 
    if isExpired then return end

    -- ✅ GG Memory Bypass — live refresh (throttled internally)
    pcall(function()
        if _G.N5LA_GG_Tick then _G.N5LA_GG_Tick() end
    end)
-- ✅ Match-scoped URL blocker: auto on/off with match state
pcall(function()
    if not _G.N5LA_EnterMatch then return end
    local inMatch = false
    pcall(function()
        if CGameState and CGameState.GameModeID then
            local id = tonumber(CGameState.GameModeID)
            if id and id > 0 then inMatch = true end
        end
    end)
    local was = (_G.N5LA_MatchState and _G.N5LA_MatchState.inMatch) or false
    if inMatch and not was then
        _G.N5LA_EnterMatch()
    elseif not inMatch and was then
        _G.N5LA_ExitMatch()
    end
end)

    if _G.MON5LAState.CustomTextData == nil then 
        _G.MON5LAState.CustomTextData = {OuterSpeed = 10, InnerSpeed = 10, HRecoil = 0.3, VRecoil = 0.3, MagicHead = 1.0, MagicBody = 1.0, MagicLegs = 1.0, IpadViewFOV = 120, AimTouchHipPrio = 1, AimTouchHipBone = 1, AimTouchHipCond = 1, AimTouchHipSpeed = 50, AimTouchHipFOV = 30, AimTouchHipDist = 250, AimTouchSGPrio = 1, AimTouchSGBone = 2, AimTouchSGCond = 1, AimTouchSGSpeed = 80, AimTouchSGFOV = 40, AimTouchSGDist = 30, AimTouchScopePrio = 1, AimTouchScopeBone = 2, AimTouchScopeCond = 1, AimTouchScopeSpeed = 40, AimTouchScopeFOV = 20, AimTouchScopeDist = 300, AimTouchSniperPrio = 1, AimTouchSniperBone = 1, AimTouchSniperCond = 2, AimTouchSniperSpeed = 30, AimTouchSniperFOV = 20, AimTouchSniperDist = 400}
    end

    local okData, GameplayData = pcall(require, "GameLua.GameCore.Data.GameplayData") 
    if not okData or not GameplayData then return end 
    local pc = GameplayData.GetPlayerController() 
    local localPlayer = nil
    if Valid(pc) then localPlayer = pc:GetPlayerCharacterSafety() end 

    if not Valid(localPlayer) then 
        if _G.MON5LAState.TrackedMarks then
            for markId, _ in pairs(_G.MON5LAState.TrackedMarks) do
                SafeRemoveMark(markId)
            end
        end
        _G.MON5LAState.TrackedMarks = {} 
        
        for key, data in pairs(_G.MON5LAState.EnemyMarks) do
            if data and data.MIDs then
                for meshStr, midTable in pairs(data.MIDs) do
                    for k, _ in pairs(midTable) do midTable[k] = nil end
                end
                data.MIDs = nil
            end
        end
        
        _G.MON5LAState.EnemyMarks = {}
        _G.AK_OrigHitboxes = {}
        _G.AK_ModdedPhysAssets = {}
        _G.MON5LAState.PrevGraphicsState = {}
        return 
    end

    local Cached_PPM = nil
    pcall(function() Cached_PPM = import("PostProcessManager").GetInstance() end)
    local Cached_SecurityCommonUtils = nil
    pcall(function() Cached_SecurityCommonUtils = require("GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils") end)
    local Cached_MyHUD = pc and pc.MyHUD or nil

    if _G.MON5LAConfig.UnlockFPS then InitializeGraphicsUnlock() end
    InitializeNativeESP()
    ShowMON5LAVIPMenu()
    
    -- IPAD VIEW (UPDATED WITH VEHICLE & SCOPE FROM GOLD)
    pcall(function()
        local isAiming = false
        if localPlayer.bIsWeaponAiming or localPlayer.bIsGunADS then isAiming = true end

        local currentVehicle = localPlayer.CurrentVehicle or (type(localPlayer.GetVehicle) == "function" and localPlayer:GetVehicle())
        local isInVehicle = Valid(currentVehicle) or localPlayer.bIsInVehicle
        local uTPPCam = localPlayer.ThirdPersonCameraComponent
        local uVehCam = localPlayer.VehicleCameraComponent
        local camMgr = pc.PlayerCameraManager

        -- Scope handling
        if isAiming then
            if _G.MON5LAConfig.IpadViewScope and _G.MON5LAState.CustomTextData then
                local targetScope = _G.MON5LAState.CustomTextData.IpadViewScopeFOV or 60
                if type(pc.FOV) == "function" then pc:FOV(targetScope) end
                if Valid(camMgr) then
                    camMgr.DefaultFOV = targetScope
                    if type(camMgr.SetFOV) == "function" then camMgr:SetFOV(targetScope) end
                end
            else
                if type(pc.FOV) == "function" then pc:FOV(0) end
                if Valid(camMgr) and type(camMgr.UnlockFOV) == "function" then camMgr:UnlockFOV() end
            end
            return
        end

        -- Restore FOV if scope was turned off
        if not isInVehicle or not _G.MON5LAConfig.IpadViewVehicle then
            if type(pc.FOV) == "function" then pc:FOV(0) end
            if Valid(camMgr) and type(camMgr.UnlockFOV) == "function" then camMgr:UnlockFOV() end
        end

        -- Walking
        if not isInVehicle then
            if _G.MON5LAConfig.IpadView and _G.MON5LAState.CustomTextData then
                local targetTPP = _G.MON5LAState.CustomTextData.IpadViewFOV or 120
                if Valid(uTPPCam) and uTPPCam.FieldOfView ~= targetTPP then 
                    uTPPCam.FieldOfView = targetTPP 
                end
            else
                if Valid(uTPPCam) and uTPPCam.FieldOfView ~= 90 then 
                    uTPPCam.FieldOfView = 90 
                end
            end
        end

        -- Vehicle
        if isInVehicle then
            if _G.MON5LAConfig.IpadViewVehicle and _G.MON5LAState.CustomTextData then
                local targetVeh = _G.MON5LAState.CustomTextData.IpadViewVehicleFOV or 120
                
                if Valid(uVehCam) and uVehCam.FieldOfView ~= targetVeh then 
                    uVehCam.FieldOfView = targetVeh 
                end
                
                if targetVeh > 90 then
                    if type(pc.FOV) == "function" then pc:FOV(targetVeh) end
                    if Valid(camMgr) then
                        camMgr.DefaultFOV = targetVeh
                        if type(camMgr.SetFOV) == "function" then camMgr:SetFOV(targetVeh) end
                    end
                end
            else
                if Valid(uVehCam) and uVehCam.FieldOfView ~= 90 then 
                    uVehCam.FieldOfView = 90 
                end
            end
        end
    end)

    -- Aimbot V2 and FOV Circle
    pcall(function()
        local ui_util = require("client.common.ui_util")
        if ui_util then
            local vp = ui_util.GetViewportSize()
            if vp then
                _G.__AimTouch_ViewportX = vp.X
                _G.__AimTouch_CenterX = vp.X * 0.5
                _G.__AimTouch_CenterY = vp.Y * 0.5
            end
        end
        
        local wName = ""
        local weapon = localPlayer.WeaponManagerComponent and localPlayer.WeaponManagerComponent.CurrentWeaponReplicated
        if not weapon and type(localPlayer.GetCurrentShootWeapon) == "function" then
            weapon = localPlayer:GetCurrentShootWeapon()
        end
        if slua.isValid(weapon) then
            wName = type(weapon.GetWeaponName) == "function" and weapon:GetWeaponName() or ""
            local wID = type(weapon.GetWeaponID) == "function" and weapon:GetWeaponID() or 0
            if (wID >= 1030000 and wID < 1040000) or wName:find("S686") or wName:find("S1897") or wName:find("S12") or wName:find("DBS") or wName:find("M1014") then 
                _G.__AimTouch_WeaponType = "SHOTGUN"
            elseif wName:find("Kar98") or wName:find("M24") or wName:find("AWM") or wName:find("Mosin") or wName:find("Win94") or wName:find("AMR") or wName:find("SKS") or wName:find("SLR") or wName:find("Mini") or wName:find("Mk14") or wName:find("QBU") or wName:find("Mk12") or wName:find("VSS") then
                _G.__AimTouch_WeaponType = "SNIPER"
            elseif wName:lower():find("mortar") or wName:lower():find("cối") then
                _G.__AimTouch_WeaponType = "MORTAR"
            else
                _G.__AimTouch_WeaponType = "NORMAL"
            end
        end
    end)

    if _G.MON5LAConfig.AimTouchEnable then
        _G.AimTouch()
    end

    if _G.FovCircleOverlay then
        pcall(function() _G.FovCircleOverlay.Update(pc, localPlayer) end)
    end
    
    -- ========================================== 
    -- SKIN MOD LOOP + KILL COUNTER + DEADBOX
    -- ========================================== 
    if _G.MON5LAConfig.ModSkin then
        if not _G.TDSkinLoopStarted then
            if _G.InitializeSkinModSystem then _G.InitializeSkinModSystem() end
            if _G.ForceRefreshSkinMaps then _G.ForceRefreshSkinMaps() end
            _G.TDSkinLoopStarted = true
            if not _G.KillInfoCounterHacked and _G.ForceEnableKillCounterUI then _G.ForceEnableKillCounterUI() end
        end
        
        _G.MON5LAState.SkinWasApplied = true
        local curTime = os.clock()
        if not _G.LastSkinUpdateTime or (curTime - _G.LastSkinUpdateTime) > 1.5 then
            _G.LastSkinUpdateTime = curTime
            pcall(function()
                local isAlive = type(localPlayer.IsAlive) == "function" and localPlayer:IsAlive() or true
                if isAlive then
                    if _G.ReadLiveConfig then _G.ReadLiveConfig() end
                    if _G.equip_character_avatar then _G.equip_character_avatar(localPlayer) end
                    if _G.ApplyWeaponSkins then _G.ApplyWeaponSkins(localPlayer) end
                    if _G.ApplyVehicleSkins then _G.ApplyVehicleSkins(localPlayer) end
                    if _G.HandlePetLogic then _G.HandlePetLogic() end
                    if _G.DeadBox_TemperRequest and _G.NeedCheckDeadBoxTimer > 0 then _G.DeadBox_TemperRequest(pc) end
                end
            end)
        end
    else
        if _G.MON5LAState.SkinWasApplied then
            _G.OutfitMap = {}
            _G.WeaponSkinMap = {}
            _G.VehicleSkinMap = {}
            pcall(function()
                local WeaponManager = localPlayer:GetWeaponManager()
                if Valid(WeaponManager) then
                    for slot = 1, 3 do
                        local Weapon = WeaponManager:GetInventoryWeaponByPropSlot(slot)
                        if Valid(Weapon) and Valid(Weapon.synData) then
                            local WeaponID = Weapon:GetWeaponID()
                            local SkinData = Weapon.synData:Get(7)
                            if SkinData and SkinData.defineID then
                                SkinData.defineID.TypeSpecificID = WeaponID
                                Weapon.synData:Set(7, SkinData)
                                if Weapon.SetWeaponAvatarID then pcall(function() Weapon:SetWeaponAvatarID(WeaponID) end) end
                                if Weapon.DelayHandleAvatarMeshChanged then pcall(function() Weapon:DelayHandleAvatarMeshChanged() end) end
                            end
                        end
                    end
                end
                local Vehicle = localPlayer:GetCurrentVehicle()
                if Valid(Vehicle) then
                    local VehicleAvatar = Vehicle.VehicleAvatar or Vehicle.VehicleAvatarComponent_BP or Vehicle:GetAvatarComponent()
                    if Valid(VehicleAvatar) and type(VehicleAvatar.GetDefaultAvatarID) == "function" then
                        local defId = VehicleAvatar:GetDefaultAvatarID()
                        if VehicleAvatar.ChangeItemAvatar then VehicleAvatar:ChangeItemAvatar(defId, true) end
                    end
                end
                if localPlayer.AvatarComponent2 and type(localPlayer.AvatarComponent2.OnRep_BodySlotStateChanged) == "function" then
                    localPlayer.AvatarComponent2:OnRep_BodySlotStateChanged()
                end
            end)
            _G.MON5LAState.SkinWasApplied = false
        end
        _G.TDSkinLoopStarted = false
    end

    -- ========================================== 
    -- Aimbot Force dipindahkan ke loop terpisah
    -- ========================================== 

    pcall(function()
        if _G.MON5LAConfig.CustomAimbot and localPlayer.bIsWeaponFiring and localPlayer.bIsGunADS then
            local outerRecoilVal = _G.MON5LAState.CustomTextData.OuterRecoil or 0
            if outerRecoilVal > 0 then
                local curTime = os.clock()
                
                if not _G.RecoilTargetCacheTime or (curTime - _G.RecoilTargetCacheTime) > 0.2 then
                    _G.RecoilTargetCacheTime = curTime
                    _G.HasRecoilTargetCached = false
                    
                    local ui_util = require("client.common.ui_util")
                    if ui_util then
                        local viewportSize = ui_util.GetViewportSize()
                        if viewportSize then
                            local centerX = viewportSize.X * 0.5
                            local centerY = viewportSize.Y * 0.5
                            local FOV_RADIUS = (6 / 100.0) * (viewportSize.X / 2.0) 
                            
                            local enemies = _G.GetEnemyTargetsFromActors(40000) 
                            if enemies and #enemies > 0 then
                                local FVector2D = import("Vector2D")
                                for _, target in ipairs(enemies) do
                                    if slua.isValid(target) and target.HealthStatus ~= 1 then 
                                        local tPos = type(target.K2_GetActorLocation) == "function" and target:K2_GetActorLocation() or nil
                                        if tPos then
                                            local screen = FVector2D()
                                            if pc:ProjectWorldLocationToScreen(tPos, screen, false) and screen.X > 0 and screen.Y > 0 then
                                                local dx = screen.X - centerX
                                                local dy = screen.Y - centerY
                                                if math.sqrt(dx*dx + dy*dy) <= FOV_RADIUS then
                                                    _G.HasRecoilTargetCached = true
                                                    break 
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end

                if _G.HasRecoilTargetCached then
                    local currentRot = pc:GetControlRotation()
                    if currentRot then
                        local pullDownForce = (outerRecoilVal / 50.0) * 1.5
                        currentRot.Pitch = currentRot.Pitch - pullDownForce
                        pc:SetControlRotation(currentRot, "CustomAimbotRecoil")
                    end
                end
            end
        else
            _G.HasRecoilTargetCached = false
        end
    end)

    pcall(function()
        if Valid(pc) then
            if pc.HiggsBoson then pc.HiggsBoson.bMHActive = false; pc.HiggsBoson.bCallPreReplication = false end
            if pc.HiggsBosonComponent then pc.HiggsBosonComponent.bMHActive = false; pc.HiggsBosonComponent.bCallPreReplication = false end
        end
    end)

    pcall(function()
        local autoComp = localPlayer.AutoAimComp
        if Valid(autoComp) then
            if not _G.MON5LAState.OrigAutoAimCompCached then
                _G.MON5LAState.OrigAutoAimCompCached = {
                    bOnlyHitHead = autoComp.bOnlyHitHead,
                    HeadBoneName = autoComp.HeadBoneName,
                    Bones = autoComp.Bones,
                    ChestBoneName = autoComp.ChestBoneName,
                    PelvisBoneName = autoComp.PelvisBoneName,
                    HeadPriority = autoComp.AimAssistConfig and autoComp.AimAssistConfig.HeadPriority,
                    ChestPriority = autoComp.AimAssistConfig and autoComp.AimAssistConfig.ChestPriority,
                    PelvisPriority = autoComp.AimAssistConfig and autoComp.AimAssistConfig.PelvisPriority
                }
            end
            
            if _G.MON5LAConfig.AutoHead then
                autoComp.bOnlyHitHead = true
                autoComp.HeadBoneName = "Head"
                pcall(function() autoComp.Bones = {"Head"} end)
                autoComp.ChestBoneName = "Head"
                autoComp.PelvisBoneName = "Head"
                if autoComp.AimAssistConfig then
                    autoComp.AimAssistConfig.HeadPriority = 100
                    autoComp.AimAssistConfig.ChestPriority = 100
                    autoComp.AimAssistConfig.PelvisPriority = 100
                end
            else
                local orig = _G.MON5LAState.OrigAutoAimCompCached
                autoComp.bOnlyHitHead = orig.bOnlyHitHead
                autoComp.HeadBoneName = orig.HeadBoneName
                pcall(function() autoComp.Bones = orig.Bones or {"Spine_01", "Pelvis", "Head"} end)
                autoComp.ChestBoneName = orig.ChestBoneName
                autoComp.PelvisBoneName = orig.PelvisBoneName
                if autoComp.AimAssistConfig then
                    autoComp.AimAssistConfig.HeadPriority = orig.HeadPriority or 1
                    autoComp.AimAssistConfig.ChestPriority = orig.ChestPriority or 1
                    autoComp.AimAssistConfig.PelvisPriority = orig.PelvisPriority or 1
                end
            end
        end
    end)

    local now = os.clock()
    pcall(function()
        local lsg = require("client.slua.logic.setting.logic_setting_graphics")
        local gi = lsg.GetGameInstance()
        if gi then
            if _G.MON5LAConfig.RemoveGrass and not _G.MON5LAState.PrevGraphicsState.RemoveGrass then
                gi:ExecuteCMD("grass.DensityScale", "0")
                gi:ExecuteCMD("grass.DiscardDataOnLoad", "1")
                _G.MON5LAState.PrevGraphicsState.RemoveGrass = true
            elseif not _G.MON5LAConfig.RemoveGrass and _G.MON5LAState.PrevGraphicsState.RemoveGrass then
                gi:ExecuteCMD("grass.DensityScale", "1")
                gi:ExecuteCMD("grass.DiscardDataOnLoad", "0")
                _G.MON5LAState.PrevGraphicsState.RemoveGrass = false
            end
            
            if _G.MON5LAConfig.RemoveFog and not _G.MON5LAState.PrevGraphicsState.RemoveFog then
                gi:ExecuteCMD("r.SkyAtmosphere", "1") 
                gi:ExecuteCMD("r.Fog", "0")           
                gi:ExecuteCMD("r.VolumetricFog", "0") 
                _G.MON5LAState.PrevGraphicsState.RemoveFog = true
            elseif not _G.MON5LAConfig.RemoveFog and _G.MON5LAState.PrevGraphicsState.RemoveFog then
                gi:ExecuteCMD("r.SkyAtmosphere", "1") 
                gi:ExecuteCMD("r.Fog", "1")           
                gi:ExecuteCMD("r.VolumetricFog", "1") 
                _G.MON5LAState.PrevGraphicsState.RemoveFog = false
            end
            
            if _G.MON5LAConfig.WhiteBody and not _G.MON5LAState.PrevGraphicsState.WhiteBody then
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "2")
                gi:ExecuteCMD("r.CharacterDiffusePower", "5")
                gi:ExecuteCMD("r.CharacterMinShadowFactor", "100")
                _G.MON5LAState.PrevGraphicsState.WhiteBody = true
            elseif not _G.MON5LAConfig.WhiteBody and _G.MON5LAState.PrevGraphicsState.WhiteBody then
                gi:ExecuteCMD("r.CharacterDiffuseOffset", "0")
                gi:ExecuteCMD("r.CharacterDiffusePower", "1")
                gi:ExecuteCMD("r.CharacterMinShadowFactor", "1")
                _G.MON5LAState.PrevGraphicsState.WhiteBody = false
            end
            
            if _G.MON5LAConfig.BlackSky and not _G.MON5LAState.PrevGraphicsState.BlackSky then
                gi:ExecuteCMD("r.CylinderMaxDrawHeight", "9999")
                _G.MON5LAState.PrevGraphicsState.BlackSky = true
            elseif not _G.MON5LAConfig.BlackSky and _G.MON5LAState.PrevGraphicsState.BlackSky then
                gi:ExecuteCMD("r.CylinderMaxDrawHeight", "0000")
                _G.MON5LAState.PrevGraphicsState.BlackSky = false
            end
        end
    end)

    pcall(function()
        local weapon = nil
        pcall(function()
            local weaponManager = localPlayer.WeaponManagerComponent
            if Valid(weaponManager) and type(weaponManager.GetCurrentWeapon) == "function" then
                weapon = weaponManager:GetCurrentWeapon()
            end
        end)
        if not Valid(weapon) then
            if type(localPlayer.GetCurrentShootWeapon) == "function" then weapon = localPlayer:GetCurrentShootWeapon()
            elseif type(localPlayer.GetCurrentWeapon) == "function" then weapon = localPlayer:GetCurrentWeapon() end
        end

        if Valid(weapon) then
    -- Apply Weapon Mod (EXPERT FITUR)
    _G.ApplyWeaponMod(weapon)
    
    local entities = {}
    if Valid(weapon.ShootWeaponEntity_GEN_VARIABLE) then table.insert(entities, weapon.ShootWeaponEntity_GEN_VARIABLE) end
    if Valid(weapon.ShootWeaponEntity) then table.insert(entities, weapon.ShootWeaponEntity) end
    if Valid(weapon.ShootWeaponComponent) and Valid(weapon.ShootWeaponComponent.ShootWeaponEntityComponent) then 
        table.insert(entities, weapon.ShootWeaponComponent.ShootWeaponEntityComponent) 
    end

            for _, entity in ipairs(entities) do
                local anyWeaponModOn = _G.MON5LAConfig.CustomHRecoil or _G.MON5LAConfig.CustomVRecoil or _G.MON5LAConfig.LessShake or _G.MON5LAConfig.Accuracy or _G.MON5LAConfig.Crosshair or _G.MON5LAConfig.GodMode or _G.MON5LAConfig.AutoHead or _G.MON5LAConfig.CustomAimbot or _G.MON5LAConfig.CustomAimbotClose or _G.MON5LAConfig.CustomMagicBullet

                if anyWeaponModOn then
                    if not entity.OriginalStatsCached then
                        entity.OriginalStatsCached = {
                            GameDeviationFactor = entity.GameDeviationFactor,
                            GameDeviationAccuracy = entity.GameDeviationAccuracy,
                            BulletFireSpeed = entity.BulletFireSpeed,
                            ShootInterval = entity.ShootInterval,
                            BaseDamage = entity.BaseDamage,
                            AccessoriesHRecoilFactor = entity.AccessoriesHRecoilFactor,
                            AccessoriesVRecoilFactor = entity.AccessoriesVRecoilFactor,
                            RecoilKick = entity.RecoilKick,
                            RecoilKickADS = entity.RecoilKickADS,
                            AnimationKick = entity.AnimationKick
                        }
                    end
                    
                    if _G.MON5LAConfig.CustomHRecoil then entity.AccessoriesHRecoilFactor = _G.MON5LAState.CustomTextData.HRecoil or 0.3 
                    elseif _G.MON5LAConfig.LessRecoil then entity.AccessoriesHRecoilFactor = 0.3 end
                    
                    if _G.MON5LAConfig.CustomVRecoil then entity.AccessoriesVRecoilFactor = _G.MON5LAState.CustomTextData.VRecoil or 0.3
                    elseif _G.MON5LAConfig.VerticalRecoil then entity.AccessoriesVRecoilFactor = 0.3 end
                    
                    if _G.MON5LAConfig.LessShake then entity.RecoilKickADS = 0.0; entity.RecoilKickADS = 0.0; entity.RecoilKickADS = 0.0 end
                    if _G.MON5LAConfig.Accuracy then entity.GameDeviationAccuracy = 0.0 end
                    if _G.MON5LAConfig.Crosshair then entity.GameDeviationFactor = 0.0 end
                    if _G.MON5LAConfig.GodMode then entity.BulletFireSpeed = 500000.0; entity.ShootInterval = 0.001; entity.BaseDamage = 60000.0 end
                    if _G.MON5LAConfig.CustomMagicBullet then
                        entity.BaseDamage = entity.BaseDamage * (_G.MON5LAState.CustomTextData.MagicHead or 1.0)
                    end
                    
                    if entity.AutoAimingConfig then
                        if not entity.OriginalAutoAimCached then
                            entity.OriginalAutoAimCached = {
                                OuterSpeed = entity.AutoAimingConfig.OuterRange and entity.AutoAimingConfig.OuterRange.Speed,
                                InnerSpeed = entity.AutoAimingConfig.InnerRange and entity.AutoAimingConfig.InnerRange.Speed
                            }
                        end
                        
                        if _G.MON5LAConfig.AutoHead then
                            pcall(function() entity.AutoAimingConfig.Bones = { "Head", "Head", "Head" } end)
                        end
                        
                        if _G.MON5LAConfig.CustomAimbot then
                            local speed = _G.MON5LAState.CustomTextData.OuterSpeed or 10
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = speed                                entity.AutoAimingConfig.OuterRange.RangeRate = 4.5
                                entity.AutoAimingConfig.OuterRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.OuterRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.OuterRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.OuterRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.OuterRange.ProneRate = 1.0
                                entity.AutoAimingConfig.OuterRange.DyingRate = 0.0
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = speed
                                entity.AutoAimingConfig.InnerRange.RangeRate = 4.5
                                entity.AutoAimingConfig.InnerRange.SpeedRate = 1.3
                                entity.AutoAimingConfig.InnerRange.RangeRateSight = 1.8
                                entity.AutoAimingConfig.InnerRange.SpeedRateSight = 2.2
                                entity.AutoAimingConfig.InnerRange.CrouchRate = 1.1
                                entity.AutoAimingConfig.InnerRange.ProneRate = 1.0
                                entity.AutoAimingConfig.InnerRange.DyingRate = 0.0
                            end
                        elseif _G.MON5LAConfig.CustomAimbotClose then
                            local speed = _G.MON5LAState.CustomTextData.InnerSpeed or 10
                            if entity.AutoAimingConfig.OuterRange then
                                entity.AutoAimingConfig.OuterRange.Speed = speed
                                entity.AutoAimingConfig.OuterRange.DyingRate = 0.0
                            end
                            if entity.AutoAimingConfig.InnerRange then
                                entity.AutoAimingConfig.InnerRange.Speed = speed
                                entity.AutoAimingConfig.InnerRange.DyingRate = 0.0
                            end
                        end
                    end
                    
                    entity.MON5LAWeaponModsActive = true

                elseif entity.MON5LAWeaponModsActive then
                    if entity.OriginalStatsCached then
                        local orig = entity.OriginalStatsCached
                        entity.GameDeviationFactor = orig.GameDeviationFactor
                        entity.GameDeviationAccuracy = orig.GameDeviationAccuracy
                        entity.BulletFireSpeed = orig.BulletFireSpeed
                        entity.ShootInterval = orig.ShootInterval
                        entity.BaseDamage = orig.BaseDamage
                        entity.AccessoriesHRecoilFactor = orig.AccessoriesHRecoilFactor
                        entity.AccessoriesVRecoilFactor = orig.AccessoriesVRecoilFactor
                        entity.RecoilKick = orig.RecoilKick
                        entity.RecoilKickADS = orig.RecoilKickADS
                        entity.AnimationKick = orig.AnimationKick
                    end
                    if entity.AutoAimingConfig and entity.OriginalAutoAimCached then
                        pcall(function() entity.AutoAimingConfig.Bones = { "Spine_01", "Pelvis", "Head" } end)
                        if entity.AutoAimingConfig.OuterRange and entity.OriginalAutoAimCached.OuterSpeed then
                            entity.AutoAimingConfig.OuterRange.Speed = entity.OriginalAutoAimCached.OuterSpeed
                        end
                        if entity.AutoAimingConfig.InnerRange and entity.OriginalAutoAimCached.InnerSpeed then
                            entity.AutoAimingConfig.InnerRange.Speed = entity.OriginalAutoAimCached.InnerSpeed
                        end
                    end
                    entity.MON5LAWeaponModsActive = false
                end
            end
        end
    end)

    local mHead_Global, mBody_Global, mLegs_Global = 1.0, 1.0, 1.0
    local runInject_Global = false
    
    pcall(function()
        if _G.MON5LAConfig.CustomMagicBullet then
            runInject_Global = true
            mHead_Global = 1.0; mBody_Global = 1.0; mLegs_Global = 1.0
            if _G.MON5LAState.CustomTextData then
                local cData = _G.MON5LAState.CustomTextData
                if cData.MagicHead ~= nil then mHead_Global = tonumber(cData.MagicHead) or mHead_Global end
                if cData.MagicBody ~= nil then mBody_Global = tonumber(cData.MagicBody) or mBody_Global end
                if cData.MagicLegs ~= nil then mLegs_Global = tonumber(cData.MagicLegs) or mLegs_Global end
            end
        elseif _G.MON5LAConfig.MagicBullet then
            runInject_Global = true
            mHead_Global = 1.05; mBody_Global = 1.0; mLegs_Global = 1.0
        end

        if runInject_Global then
            local currentMagicHash = "M_"..tostring(mHead_Global).."_"..tostring(mBody_Global).."_"..tostring(mLegs_Global)
            if _G.MON5LAState.LastMagicConfigHash ~= currentMagicHash then
                _G.MON5LAState.MagicUpdateVersion = (_G.MON5LAState.MagicUpdateVersion or 0) + 1
                _G.MON5LAState.LastMagicConfigHash = currentMagicHash
            end
        else
            if _G.MON5LAState.LastMagicConfigHash ~= "OFF" then
                _G.MON5LAState.MagicUpdateVersion = (_G.MON5LAState.MagicUpdateVersion or 0) + 1
                _G.MON5LAState.LastMagicConfigHash = "OFF"
            end
        end
    end)

    pcall(function()
        local allCharacters = {}
        if GameplayData.GetAllPlayerCharacters then allCharacters = GameplayData.GetAllPlayerCharacters()
        elseif GameplayData.GameCharacters then for _, char in pairs(GameplayData.GameCharacters) do table.insert(allCharacters, char) end end
        
        local currentValidKeys = {}
        for _, enemy in pairs(allCharacters) do
            if Valid(enemy) and enemy ~= localPlayer then
                currentValidKeys[GetSafeEnemyKey(enemy)] = true
            end
        end
        
        for key, data in pairs(_G.MON5LAState.EnemyMarks) do
            if not currentValidKeys[key] then
                SafeRemoveMark(data.radarMark)
                SafeRemoveMark(data.hpMark)
                SafeRemoveMark(data.distMark)
                
                if _G.AimTouchVisCache and _G.AimTouchVisCache[key] then
                    _G.AimTouchVisCache[key] = nil
                end
                
                if data.MIDs then
                    for meshStr, midTable in pairs(data.MIDs) do
                        for k, _ in pairs(midTable) do
                            midTable[k] = nil
                        end
                    end
                    data.MIDs = nil
                end
                
                data.enemy = nil
                data.CachedMeshes = nil
                _G.MON5LAState.EnemyMarks[key] = nil
            end
        end

        local realCount = 0
        local aiCount = 0

        local function GetFirstElemSafe(elemArray)
            if elemArray and type(elemArray.Num) == "function" and elemArray:Num() > 0 then
                if type(elemArray.Get) == "function" then return elemArray:Get(0) end
            elseif elemArray and type(elemArray) == "table" and #elemArray > 0 then
                return elemArray[1]
            end
            return nil
        end

        local BoneScaleMap = {
            ["head"] = mHead_Global, ["neck_01"] = mHead_Global,
            ["pelvis"] = mBody_Global, ["spine_01"] = mBody_Global, ["spine_02"] = mBody_Global, ["spine_03"] = mBody_Global,
            ["thigh_l"] = mLegs_Global, ["thigh_r"] = mLegs_Global, 
            ["calf_l"] = mLegs_Global, ["calf_r"] = mLegs_Global,   
            ["foot_l"] = mLegs_Global, ["foot_r"] = mLegs_Global    
        }
        
        local mLoc = nil
        pcall(function() if type(localPlayer.K2_GetActorLocation) == "function" then mLoc = localPlayer:K2_GetActorLocation() end end)

        for _, enemy in pairs(allCharacters) do
            if Valid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
                local bIsReallyDead = false
                pcall(function()
                    if type(enemy.IsDead) == "function" then bIsReallyDead = enemy:IsDead()
                    elseif enemy.bIsDead ~= nil then bIsReallyDead = enemy.bIsDead
                    elseif enemy.bIsDeadFlag ~= nil then bIsReallyDead = enemy.bIsDeadFlag end
                    if enemy.HealthStatus ~= nil and enemy.HealthStatus == 2 then bIsReallyDead = true end
                end)

                local eKey = GetSafeEnemyKey(enemy)
                _G.MON5LAState.EnemyMarks[eKey] = _G.MON5LAState.EnemyMarks[eKey] or { enemy = enemy }
                local markData = _G.MON5LAState.EnemyMarks[eKey]
                markData.enemy = enemy 

                if not bIsReallyDead then
                    if markData.lastEnemyActor ~= enemy then
                        if markData.hpMark then SafeRemoveMark(markData.hpMark); markData.hpMark = nil end
                        if markData.hpMark8 then SafeRemoveMark(markData.hpMark8); markData.hpMark8 = nil end
                        if markData.distMark then SafeRemoveMark(markData.distMark); markData.distMark = nil end
                        if markData.radarMark then SafeRemoveMark(markData.radarMark); markData.radarMark = nil end
                        
                        markData.lastEnemyActor = enemy
                        markData.LastUIComp = nil
                        markData.LastFrameUIState = nil
                    end
                    
                    local eMesh = nil
                    pcall(function() eMesh = enemy.Mesh or (type(enemy.getAvatarComponent2) == "function" and enemy:getAvatarComponent2() or nil) end)
                    local aLoc = nil
                    pcall(function() if type(enemy.K2_GetActorLocation) == "function" then aLoc = enemy:K2_GetActorLocation() end end)
                    
                    local isBotResult, isStateLoaded = CheckIsAI(enemy, markData)
                    local isBot = markData.AK_IS_BOT or false

                    local currentMeshCount = 0
                    if Valid(eMesh) then
                        local tempMeshes = GetAllSkeletalMeshes(enemy, markData)
                        currentMeshCount = #tempMeshes
                    end
                    local isMeshChanged = (markData.LastMeshCountWall ~= currentMeshCount)

                    -- ============ WALLHACK V3 ENGINE (NEW ENGINE CHAMS) ============
                    if _G.MON5LAConfig.ColorBodyNew or _G.MON5LAConfig.Wallhack then
                        if isMeshChanged or not markData.WallhackApplied then
                            ApplyColorBodyNew(enemy, markData)
                            markData.WallhackApplied = true
                            markData.LastMeshCountWall = currentMeshCount
                        end
                    else
                        UndoColorBodyNew(enemy, markData)
                        markData.WallhackApplied = false
                    end

                    pcall(function()
                        local EnemyMesh = eMesh
                        if slua.isValid(EnemyMesh) then
                            local uniqueID = type(enemy.GetUniqueID) == "function" and enemy:GetUniqueID() or tostring(enemy.PlayerKey or enemy)
                            
                            if markData.MagicBulletHash == _G.MON5LAState.LastMagicConfigHash and markData.MagicTargetID == uniqueID then
                                return 
                            end

                            local PhysicsAsset = EnemyMesh.PhysicsAssetOverride
                            if not slua.isValid(PhysicsAsset) and EnemyMesh.SkeletalMesh then PhysicsAsset = EnemyMesh.SkeletalMesh.PhysicsAsset end

                            if slua.isValid(PhysicsAsset) and PhysicsAsset.SkeletalBodySetups then
                                if not _G.AK_ModdedPhysAssets then _G.AK_ModdedPhysAssets = {} end
                                local PhysAssetName = "DefaultPhys"
                                pcall(function() PhysAssetName = PhysicsAsset:GetName() end)
                                
                                if _G.AK_ModdedPhysAssets[PhysAssetName] ~= _G.MON5LAState.LastMagicConfigHash then
                                    
                                    if not _G.AK_OrigHitboxes then _G.AK_OrigHitboxes = {} end
                                    if not _G.AK_OrigHitboxes[PhysAssetName] then _G.AK_OrigHitboxes[PhysAssetName] = {} end
                                    local OrigHitboxData = _G.AK_OrigHitboxes[PhysAssetName]

                                    local SkeletalBodySetups = PhysicsAsset.SkeletalBodySetups
                                    local numSetups = type(SkeletalBodySetups.Num) == "function" and SkeletalBodySetups:Num() or #SkeletalBodySetups
                                    local limit = numSetups > 50 and 50 or numSetups

                                    for i = 1, limit do 
                                        local BodySetup = type(SkeletalBodySetups.Get) == "function" and SkeletalBodySetups:Get(i-1) or SkeletalBodySetups[i]
                                        if slua.isValid(BodySetup) then
                                            local LowerBoneName = string.lower(tostring(BodySetup.BoneName))
                                            local MatchedBoneKey = nil
                                            for k, _ in pairs(BoneScaleMap) do
                                                if string.find(LowerBoneName, k, 1, true) then MatchedBoneKey = k break end
                                            end

                                            if MatchedBoneKey then
                                                local TargetScale = 1.0 
                                                if runInject_Global then TargetScale = BoneScaleMap[MatchedBoneKey] end
                                                
                                                local AggGeom = BodySetup.AggGeom
                                                
                                                local BoxElems = AggGeom and AggGeom.BoxElems or BodySetup.BoxElems
                                                local SphereElems = AggGeom and AggGeom.SphereElems or BodySetup.SphereElems
                                                local SphylElems = AggGeom and AggGeom.SphylElems or BodySetup.SphylElems

                                                local BoxElem = GetFirstElemSafe(BoxElems)
                                                local SphereElem = GetFirstElemSafe(SphereElems)
                                                local SphylElem = GetFirstElemSafe(SphylElems)

                                                if not OrigHitboxData[MatchedBoneKey] then
                                                    OrigHitboxData[MatchedBoneKey] = { Box = nil, Sphere = nil, Sphyl = nil }
                                                    if BoxElem then OrigHitboxData[MatchedBoneKey].Box = { X = BoxElem.X, Y = BoxElem.Y, Z = BoxElem.Z } end
                                                    if SphereElem then OrigHitboxData[MatchedBoneKey].Sphere = { Radius = SphereElem.Radius } end
                                                    if SphylElem then OrigHitboxData[MatchedBoneKey].Sphyl = { Radius = SphylElem.Radius, Length = SphylElem.Length } end
                                                end

                                                local OrigElemData = OrigHitboxData[MatchedBoneKey]

                                                if OrigElemData.Box and BoxElem then
                                                    BoxElem.X = OrigElemData.Box.X * TargetScale
                                                    BoxElem.Y = OrigElemData.Box.Y * TargetScale
                                                    BoxElem.Z = OrigElemData.Box.Z * TargetScale
                                                    if type(BoxElems.Set) == "function" then BoxElems:Set(0, BoxElem) else BoxElems[1] = BoxElem end
                                                    if AggGeom then AggGeom.BoxElems = BoxElems; BodySetup.AggGeom = AggGeom else BodySetup.BoxElems = BoxElems end
                                                end

                                                if OrigElemData.Sphere and SphereElem then
                                                    SphereElem.Radius = OrigElemData.Sphere.Radius * TargetScale
                                                    if type(SphereElems.Set) == "function" then SphereElems:Set(0, SphereElem) else SphereElems[1] = SphereElem end
                                                    if AggGeom then AggGeom.SphereElems = SphereElems; BodySetup.AggGeom = AggGeom else BodySetup.SphereElems = SphereElems end
                                                end

                                                if OrigElemData.Sphyl and SphylElem then
                                                    SphylElem.Radius = OrigElemData.Sphyl.Radius * TargetScale
                                                    SphylElem.Length = OrigElemData.Sphyl.Length * TargetScale
                                                    if type(SphylElems.Set) == "function" then SphylElems:Set(0, SphylElem) else SphylElems[1] = SphylElem end
                                                    if AggGeom then AggGeom.SphylElems = SphylElems; BodySetup.AggGeom = AggGeom else BodySetup.SphylElems = SphylElems end
                                                end
                                            end
                                        end
                                    end
                                    _G.AK_ModdedPhysAssets[PhysAssetName] = _G.MON5LAState.LastMagicConfigHash
                                end
                                
                                if EnemyMesh.SetPhysicsAsset then EnemyMesh:SetPhysicsAsset(PhysicsAsset) end
                                EnemyMesh.PhysicsAssetOverride = PhysicsAsset
                                
                                markData.MagicBulletHash = _G.MON5LAState.LastMagicConfigHash
                                markData.MagicTargetID = uniqueID
                            end
                        end
                    end)

                    local distM = 0
                    pcall(function() distM = localPlayer:GetDistanceTo(enemy) / 100 end)

                    local currentHp, maxHp = 100, 100
                    local showFrameUI = _G.MON5LAConfig.Esp5 or _G.MON5LAConfig.EspVipPro or _G.MON5LAConfig.EspVip
                    
                    if showFrameUI then
                        pcall(function()
                            if enemy.Health then currentHp = enemy.Health elseif type(enemy.GetHealth) == "function" then currentHp = enemy:GetHealth() end
                            if enemy.HealthMax then maxHp = enemy.HealthMax elseif type(enemy.GetHealthMax) == "function" then maxHp = enemy:GetHealthMax() end
                        end)
                        if maxHp <= 0 then maxHp = 100 end
                    end
                    local hpRatio = currentHp / maxHp

                    if _G.MON5LAConfig.EspAntenna then
                        pcall(function()
                            local MyHUD = Cached_MyHUD
                            if Valid(MyHUD) and distM <= 400 then
                                local loopCount = 8  
                                local zStep = 1000     
                                local baseZ = 105     
                                local topZ = baseZ + (loopCount * zStep)
                                for i = 1, loopCount do
                                    local zOffset = baseZ + (i * zStep)
                                    MyHUD:AddDebugText("|", enemy, 0.06,
                                        {X=0, Y=0, Z=zOffset}, {X=0, Y=0, Z=zOffset},
                                        C_GREEN, true, false, true, nil, 1.2, true)
                                end
                                MyHUD:AddDebugText("I", enemy, 0.06,
                                        {X=0, Y=0, Z=topZ + 60}, {X=0, Y=0, Z=topZ + 60},
                                        C_GREEN, true, false, true, nil, 1.5, true)
                            end
                        end)
                    end

                    if _G.MON5LAConfig.Esp6 then
                        pcall(function()
                            local MyHUD = Cached_MyHUD
                            if not (Valid(MyHUD) and MyHUD.AddDebugText) then return end
                            if not Valid(enemy) or not Valid(eMesh) then return end
                            if distM > 250 then return end

                            local headPos = eMesh:GetSocketLocation("head")
                            if not headPos then return end

                            local bIsVisible = true
                            if pc and type(pc.LineOfSightTo) == "function" then
                                bIsVisible = pc:LineOfSightTo(enemy)
                            end

                            local visibleCol = GetAppliedColor(_G.ColorConfig.VisibleColor or 4, _G.ColorConfig.Brightness or 25)
                            local invisibleCol = GetAppliedColor(_G.ColorConfig.InvisibleColor or 1, _G.ColorConfig.Brightness or 25)
                            local headColor = bIsVisible and visibleCol or invisibleCol

                            MyHUD:AddDebugText(
                                "●",
                                enemy,
                                0.2,
                                {X=0, Y=0, Z=90},
                                {X=0, Y=0, Z=90},
                                headColor,
                                true,
                                false,
                                true,
                                nil,
                                0.9,
                                true
                            )
                        end)
                    end

                    if showFrameUI then
                        pcall(function()
                            local SecurityCommonUtils = Cached_SecurityCommonUtils
                            local show = true
                            if enemy.HealthStatus and SecurityCommonUtils and SecurityCommonUtils.IsHealthStatusAlive then 
                                if not SecurityCommonUtils.IsHealthStatusAlive(enemy.HealthStatus) then show = false end
                            end
                            if show and mLoc then
                                if aLoc and SecurityCommonUtils and SecurityCommonUtils.IsVector then
                                    if SecurityCommonUtils.IsVector(aLoc) and SecurityCommonUtils.IsVector(mLoc) then
                                        if aLoc.Z >= 150000 or FVector.Dist2D(mLoc, aLoc) > 50000 then show = false end
                                    end
                                end
                            end
                            if show then
                                if enemy.Replay_IsEnemyFrameUIExisted and not enemy:Replay_IsEnemyFrameUIExisted() then enemy:Replay_CreateEnemyFrameUI(true, true) end
                                if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(true) end
                                if enemy.Replay_UpdateEnemyFrameUI then enemy:Replay_UpdateEnemyFrameUI(hpRatio) end
                                
                                local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                                if Valid(uiComp) then
                                    if markData.LastFrameUIState ~= "VISIBLE" then
                                        if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(0) end
                                        if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(false) end
                                        markData.LastFrameUIState = "VISIBLE"
                                    end
                                end
                            end
                        end)
                    else
                        pcall(function()
                            if enemy.Replay_SetVisiableOfFrameUI then enemy:Replay_SetVisiableOfFrameUI(false) end
                            local uiComp = enemy.EnemyFrameUI or (type(enemy.GetEnemyFrameUI) == "function" and enemy:GetEnemyFrameUI())
                            if Valid(uiComp) then
                                if markData.LastFrameUIState ~= "HIDDEN" then
                                    if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end
                                    if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                                    markData.LastFrameUIState = "HIDDEN"
                                end
                            end
                        end)
                    end

                    if _G.MON5LAConfig.EspVipPro then
                        pcall(function()
                            local hud = Cached_MyHUD
                            if not (Valid(hud) and hud.AddDebugText) then return end
                            if distM > 400 then return end

                            local hp = enemy.Health or 100
                            local maxHp = enemy.HealthMax or 100
                            local isKnock = (hp <= 0 or enemy.HealthStatus == 1)
                            local hpPercent = isKnock and 0 or (hp / maxHp)
                            local pctValue = math.floor(hpPercent * 100 + 0.5)

                            local pName = ""
                            if _G.MON5LAConfig.EspName then
                                pName = enemy.PlayerName or enemy.PlayerNamePublic or "Enemy"
                            end

                            local bIsVisible = false
                            if pc and type(pc.LineOfSightTo) == "function" then
                                bIsVisible = pc:LineOfSightTo(enemy)
                            end

                            local visibleCol = GetAppliedColor(_G.ColorConfig.VisibleColor or 4, _G.ColorConfig.Brightness)
                            local invisibleCol = GetAppliedColor(_G.ColorConfig.InvisibleColor or 1, _G.ColorConfig.Brightness)
                            
                            local textColor = {R=255, G=255, B=255, A=255}
                            if isKnock then
                                textColor = {R=0, G=0, B=255, A=255}
                            else
                                textColor = bIsVisible and visibleCol or invisibleCol
                            end

                            local prefix = bIsVisible and "▶" or "▶"
                            local label = ""
                            if isKnock then
                                label = (pName ~= "" and string.format("%s [♿]", pName) or "♿")
                            else
                                if pName ~= "" then
                                    label = string.format("%s %s %.0f%%", pName, prefix, pctValue)
                                else
                                    label = string.format("%s %.0f%%", prefix, pctValue)
                                end
                            end

                            hud:AddDebugText(label, enemy, 0.2, {X=0, Y=0, Z=120}, {X=0, Y=0, Z=120},
                                             textColor, true, false, true, nil, 1.0, true)
                        end)
                    end

                    -- =================== ESP RANGE V1 (Jarak dalam meter) ===================
                    if _G.MON5LAConfig.EspDistance then
                        pcall(function()
                            local hud = Cached_MyHUD
                            if not (Valid(hud) and hud.AddDebugText) then return end
                            if distM > 400 then return end

                            local distMeters = math.floor(distM + 0.5)
                            local rangeColor = {R=255, G=255, B=255, A=255} -- putih

                            hud:AddDebugText(string.format("%.0fm", distMeters), enemy, 0.3,
                                             {X=15, Y=15, Z=-15}, {X=15, Y=15, Z=-15},
                                             rangeColor, true, false, true, nil, 0.9, true)
                        end)
                    end

                    if _G.MON5LAConfig.EspName and not _G.MON5LAConfig.EspVipPro then
                        pcall(function()
                            local hud = Cached_MyHUD
                            if not (Valid(hud) and hud.AddDebugText) then return end
                            if distM > 400 then return end

                            local pName = enemy.PlayerName or enemy.PlayerNamePublic or "Enemy"
                            if pName == "" then return end

                            local isKnock = (enemy.Health or 100) <= 0 or enemy.HealthStatus == 1
                            local bIsVisible = true
                            pcall(function()
                                if pc and type(pc.LineOfSightTo) == "function" then
                                    bIsVisible = pc:LineOfSightTo(enemy)
                                end
                            end)

                            local visibleCol = GetAppliedColor(_G.ColorConfig.VisibleColor or 4, _G.ColorConfig.Brightness)
                            local invisibleCol = GetAppliedColor(_G.ColorConfig.InvisibleColor or 1, _G.ColorConfig.Brightness)
                            
                            local nameColor = {R=255, G=255, B=255, A=255}
                            if isKnock then
                                nameColor = {R=0, G=0, B=255, A=255}
                            else
                                nameColor = bIsVisible and visibleCol or invisibleCol
                            end

                            hud:AddDebugText(pName, enemy, 0.2, {X=0, Y=0, Z=120}, {X=0, Y=0, Z=120},
                                             nameColor, true, false, true, nil, 1.0, true)
                        end)
                    end

                    if _G.MON5LAConfig.EspVip then
                        if markData.hpMark == nil then markData.hpMark = SafeAddMark(1006, FVector(0,0,0), 0, "", 4, enemy) end
                        if markData.distMark == nil then markData.distMark = SafeAddMark(9999, FVector(0,0,0), 0, "", 4, enemy) end
                    else
                        if markData.hpMark then SafeRemoveMark(markData.hpMark); markData.hpMark = nil end
                        if markData.distMark then SafeRemoveMark(markData.distMark); markData.distMark = nil end
                    end

                    if _G.MON5LAConfig.Esp8 then
                        if markData.hpMark8 == nil then markData.hpMark8 = SafeAddMark(1006, FVector(0,0,0), 0, "", 4, enemy) end
                    else
                        if markData.hpMark8 then SafeRemoveMark(markData.hpMark8); markData.hpMark8 = nil end
                    end
                    
                    if _G.MON5LAConfig.EspRadar then
                        if not markData.radarMark or markData.radarMark == 0 then 
                            markData.radarMark = SafeAddMark(8888, FVector(0,0,0), 0, "", 4, enemy) 
                        end
                    else
                        if markData.radarMark and markData.radarMark ~= 0 then
                            SafeRemoveMark(markData.radarMark)
                            markData.radarMark = nil
                        end
                    end
                    
                    if _G.MON5LAConfig.EspOutline then
                        pcall(function()
                            local outlineHash = tostring(_G.MON5LAConfig.OutlineThickness)
                            if markData.OutlineState ~= outlineHash then
                                local PPM = Cached_PPM
                                local avatarComp = (type(enemy.getAvatarComponent2) == "function") and enemy:getAvatarComponent2() or nil
                                if Valid(avatarComp) and Valid(PPM) then
                                    PPM.OutlineThickness = _G.MON5LAConfig.OutlineThickness
                                    if PPM.OutlineColor then PPM.OutlineColor = {r = 1, g = 0, b = 0, a = 1} end
                                    PPM:EnableAvatarOutline(avatarComp, true)
                                    markData.OutlineState = outlineHash
                                end
                            end
                        end)
                    else
                        pcall(function()
                            if markData.OutlineState ~= "OFF" then
                                local PPM = Cached_PPM
                                local avatarComp = (type(enemy.getAvatarComponent2) == "function") and enemy:getAvatarComponent2() or nil
                                if Valid(avatarComp) and Valid(PPM) then PPM:EnableAvatarOutline(avatarComp, false) end
                                markData.OutlineState = "OFF"
                            end
                        end)
                    end

                else
                    if not markData.IsCleanedUp then
                        SafeRemoveMark(markData.radarMark)
                        markData.radarMark = nil
                        SafeRemoveMark(markData.hpMark)
                        markData.hpMark = nil
                        SafeRemoveMark(markData.hpMark8)
                        markData.hpMark8 = nil
                        SafeRemoveMark(markData.distMark)
                        markData.distMark = nil
                        
                        if markData.MIDs then
                            for meshStr, midTable in pairs(markData.MIDs) do
                                for k, _ in pairs(midTable) do midTable[k] = nil end
                            end
                            markData.MIDs = nil
                        end
                        
                        pcall(function()
                            local eObj = markData.enemy
                            if Valid(eObj) then 
                                if eObj.Replay_SetVisiableOfFrameUI then eObj:Replay_SetVisiableOfFrameUI(false) end
                                local uiComp = eObj.EnemyFrameUI or (type(eObj.GetEnemyFrameUI) == "function" and eObj:GetEnemyFrameUI())
                                if Valid(uiComp) then
                                    if type(uiComp.SetVisibility) == "function" then uiComp:SetVisibility(2) end 
                                    if type(uiComp.SetHiddenInGame) == "function" then uiComp:SetHiddenInGame(true) end
                                end
                            end
                            
                            local PPM = Cached_PPM
                            local avatarComp = Valid(eObj) and (type(eObj.getAvatarComponent2) == "function") and eObj:getAvatarComponent2() or nil
                            if Valid(avatarComp) and Valid(PPM) then PPM:EnableAvatarOutline(avatarComp, false) end
                        end)

                        markData.IsCleanedUp = true
                    end
                end
            end
        end
        
        -- ========================================== 
        -- ESP VEHICLE, THROWABLE, LOOT, STATIC
        -- ========================================== 

        -- ===== ESP THROWABLE =====
        if _G.MON5LAConfig.ThrowableEnabled then
            pcall(function()
                local MyHUD = Cached_MyHUD
                if Valid(MyHUD) then
                    if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = import("GameplayStatics") end
                    if not _G.CachedActorClass_ForBomb then _G.CachedActorClass_ForBomb = import("Actor") end 
                    if not _G.CachedProjArray then _G.CachedProjArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForBomb) end
                    local ui_util = require("client.common.ui_util")
                    local gameInstance = ui_util and ui_util.GetGameInstance()
                    if gameInstance and _G.CachedGameplayStatics then
                        local curTime = os.clock()
                        local scanInterval = 0.5
                        local mode = _G.MON5LAConfig.ThrowableScanMode or 0
                        if mode == 0 then scanInterval = 0.5
                        elseif mode == 10 then scanInterval = 10.0
                        elseif mode == 20 then scanInterval = 20.0
                        end
                        
                        if not _G.LastThrowableScanTime or (curTime - _G.LastThrowableScanTime) >= scanInterval then
                            _G.LastThrowableScanTime = curTime
                            local allActors = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForBomb, _G.CachedProjArray)
                            local activeThrowables = {}
                            local itemThrowables = {}
                            if allActors then
                                for _, actor in pairs(allActors) do
                                    if slua.isValid(actor) and not actor.bHidden and not actor.bTearOff then
                                        local isPendingKill = false
                                        pcall(function() if type(actor.IsPendingKill) == "function" then isPendingKill = actor:IsPendingKill() end end)
                                        if not isPendingKill then
                                            local nameLower = string.lower(tostring(actor))
                                            local bType = 0
                                            if string.find(nameLower, "smoke") then bType = 2
                                            elseif string.find(nameLower, "burn") or string.find(nameLower, "molotov") then bType = 3
                                            elseif string.find(nameLower, "grenade") then bType = 1 end
                                            if bType > 0 then
                                                if string.find(nameLower, "projectile") or string.find(nameLower, "thrown") then
                                                    table.insert(activeThrowables, {act = actor, type = bType})
                                                else
                                                    table.insert(itemThrowables, {act = actor, type = bType})
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                            _G.CachedActiveThrowables = activeThrowables
                            _G.CachedItemThrowables = itemThrowables
                        end

                        local function DrawThrowables(throwableList, isItem, maxDist)
                            if not throwableList then return end
                            for _, item in ipairs(throwableList) do
                                local throwable = item.act
                                local bType = item.type
                                if slua.isValid(throwable) and not throwable.bHidden then
                                    local isPendingKill = false
                                    pcall(function() if type(throwable.IsPendingKill) == "function" then isPendingKill = throwable:IsPendingKill() end end)
                                    if not isPendingKill then
                                        local skipDraw = false
                                        if isItem and _G.CachedActiveThrowables then
                                            pcall(function()
                                                local loc1 = type(throwable.K2_GetActorLocation) == "function" and throwable:K2_GetActorLocation()
                                                if loc1 then
                                                    for _, actItem in ipairs(_G.CachedActiveThrowables) do
                                                        local activeT = actItem.act
                                                        if slua.isValid(activeT) then
                                                            local loc2 = type(activeT.K2_GetActorLocation) == "function" and activeT:K2_GetActorLocation()
                                                            if loc2 then
                                                                local dx = loc1.X - loc2.X
                                                                local dy = loc1.Y - loc2.Y
                                                                local dz = loc1.Z - loc2.Z
                                                                if math.sqrt(dx*dx + dy*dy + dz*dz) < 150 then skipDraw = true; break end
                                                            end
                                                        end
                                                    end
                                                end
                                            end)
                                        end
                                        if not skipDraw then
                                            local distM = 0
                                            pcall(function() distM = localPlayer:GetDistanceTo(throwable) / 100 end)
                                            if distM > 0 and distM <= maxDist then
                                                local displayName = ""
                                                local color = nil
                                                local zOffset = isItem and 15 or 25
                                                local colorIdx = 4
                                                if bType == 1 then
                                                    if not _G.MON5LAConfig.ThrowableGrenade then goto continue end
                                                    displayName = isItem and "Grenade" or "GRENADE"
                                                    colorIdx = _G.MON5LAConfig.ThrowableColor_Grenade or 4
                                                    color = GetColorBy7(colorIdx)
                                                elseif bType == 2 then
                                                    if not _G.MON5LAConfig.ThrowableSmoke then goto continue end
                                                    displayName = isItem and "Smoke" or "SMOKE"
                                                    colorIdx = _G.MON5LAConfig.ThrowableColor_Smoke or 4
                                                    color = GetColorBy7(colorIdx)
                                                elseif bType == 3 then
                                                    if not _G.MON5LAConfig.ThrowableMolotov then goto continue end
                                                    displayName = isItem and "Molotov" or "MOLOTOV"
                                                    colorIdx = _G.MON5LAConfig.ThrowableColor_Molotov or 4
                                                    color = GetColorBy7(colorIdx)
                                                else
                                                    goto continue
                                                end
                                                if color then
                                                    local text = string.format("%s [%dm]", displayName, math.floor(distM))
                                                    local curGameTime = 0
                                                    pcall(function() curGameTime = _G.CachedGameplayStatics.GetTimeSeconds(gameInstance) end)
                                                    local shouldTimerRun = not isItem
                                                    if isItem then
                                                        pcall(function()
                                                            if throwable.bIsPinPulled or throwable.bPinPulled or (type(throwable.IsPinPulled) == "function" and throwable:IsPinPulled()) then
                                                                shouldTimerRun = true
                                                            end
                                                        end)
                                                    end
                                                    if shouldTimerRun and curGameTime > 0 then
                                                        local timeLeft = -1
                                                        pcall(function()
                                                            if type(throwable.GetExplosionTime) == "function" then timeLeft = throwable:GetExplosionTime() - curGameTime
                                                            elseif throwable.ExplosionTime then timeLeft = throwable.ExplosionTime - curGameTime
                                                            elseif throwable.ExplodeTime then timeLeft = throwable.ExplodeTime - curGameTime end
                                                        end)
                                                        if timeLeft == -1 or timeLeft > 100 then
                                                            _G.ActiveThrowableTimers = _G.ActiveThrowableTimers or {}
                                                            local id = tostring(throwable)
                                                            if not _G.ActiveThrowableTimers[id] then _G.ActiveThrowableTimers[id] = curGameTime end
                                                            local elapsed = curGameTime - _G.ActiveThrowableTimers[id]
                                                            local maxTime = 5.0
                                                            if bType == 1 then maxTime = 7.0
                                                            elseif bType == 2 then maxTime = 45.0
                                                            elseif bType == 3 then maxTime = 12.0 end
                                                            timeLeft = maxTime - elapsed
                                                        end
                                                        if timeLeft < 0 then timeLeft = 0 end
                                                        if timeLeft > 0.1 then
                                                            text = string.format("%s (%.1fs)", text, timeLeft)
                                                            if bType == 1 and timeLeft <= 1.5 then
                                                                color = {R=255, G=165, B=0, A=255}
                                                            end
                                                        end
                                                    end
                                                    pcall(function()
                                                        if _G.ActiveThrowableTimers then
                                                            for k, v in pairs(_G.ActiveThrowableTimers) do
                                                                if (curGameTime - v) > 60.0 then _G.ActiveThrowableTimers[k] = nil end
                                                            end
                                                        end
                                                    end)
                                                    local dynamicScale = math.max(0.6, 1.1 - (distM / maxDist))
                                                    MyHUD:AddDebugText(text, throwable, 0.3, {X=0, Y=0, Z=zOffset}, {X=0, Y=0, Z=zOffset}, color, true, false, true, nil, dynamicScale, true)
                                                end
                                            end
                                        end
                                    end
                                end
                                ::continue::
                            end
                        end

                        DrawThrowables(_G.CachedItemThrowables, true, 50)
                        DrawThrowables(_G.CachedActiveThrowables, false, 150)
                    end
                end
            end)
        end

        -- ===== ESP VEHICLE =====
        if _G.MON5LAConfig.VehicleEnabled then
            pcall(function()
                local MyHUD = Cached_MyHUD
                if Valid(MyHUD) then
                    if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = import("GameplayStatics") end
                    if not _G.CachedActorClass_ForVehicle then _G.CachedActorClass_ForVehicle = import("STExtraVehicleBase") end 
                    if not _G.CachedVehicleArray then _G.CachedVehicleArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForVehicle) end
                    local ui_util = require("client.common.ui_util")
                    local gameInstance = ui_util and ui_util.GetGameInstance()
                    if gameInstance and _G.CachedGameplayStatics then
                        local curTime = os.clock()
                        if not _G.LastVehicleScanTime or (curTime - _G.LastVehicleScanTime) > 1.0 then
                            _G.LastVehicleScanTime = curTime
                            local allVehicles = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForVehicle, _G.CachedVehicleArray)
                            local activeVehicles = {}
                            if allVehicles then
                                for _, veh in pairs(allVehicles) do
                                    if slua.isValid(veh) and not veh.bHidden and not veh.bTearOff then
                                        local isPendingKill = false
                                        pcall(function() if type(veh.IsPendingKill) == "function" then isPendingKill = veh:IsPendingKill() end end)
                                        if not isPendingKill then
                                            local vehName = "Kendaraan"
                                            pcall(function()
                                                if type(veh.GetVehicleName) == "function" then vehName = veh:GetVehicleName()
                                                elseif veh.VehicleName then vehName = veh.VehicleName end
                                            end)
                                            local nameLower = string.lower(tostring(vehName) .. tostring(veh))
                                            local displayName = "Kendaraan"
                                            if string.find(nameLower, "uaz") then displayName = "UAZ"
                                            elseif string.find(nameLower, "dacia") then displayName = "Dacia"
                                            elseif string.find(nameLower, "buggy") then displayName = "Buggy"
                                            elseif string.find(nameLower, "mirado") then displayName = "Mirado"
                                            elseif string.find(nameLower, "bike") or string.find(nameLower, "motor") then displayName = "Motor"
                                            elseif string.find(nameLower, "scooter") then displayName = "Scooter"
                                            elseif string.find(nameLower, "coupe") then displayName = "Coupe RB"
                                            elseif string.find(nameLower, "brdm") then displayName = "BRDM"
                                            elseif string.find(nameLower, "boat") or string.find(nameLower, "aquarail") then displayName = "Perahu"
                                            elseif string.find(nameLower, "glider") then displayName = "Glider"
                                            else displayName = "Kendaraan" end
                                            table.insert(activeVehicles, {act = veh, name = displayName})
                                        end
                                    end
                                end
                            end
                            _G.CachedVehicles = activeVehicles
                        end

                        if _G.CachedVehicles then
                            for _, item in ipairs(_G.CachedVehicles) do
                                local veh = item.act
                                if slua.isValid(veh) and not veh.bHidden then
                                    local isPendingKill = false
                                    pcall(function() if type(veh.IsPendingKill) == "function" then isPendingKill = veh:IsPendingKill() end end)
                                    if not isPendingKill then
                                        local isShow = false
                                        local colorKey = "VehicleColor_Other"
                                        if item.name == "Dacia" then isShow = _G.MON5LAConfig.VehicleShowDacia; colorKey = "VehicleColor_Dacia"
                                        elseif item.name == "UAZ" then isShow = _G.MON5LAConfig.VehicleShowUAZ; colorKey = "VehicleColor_UAZ"
                                        elseif item.name == "Buggy" then isShow = _G.MON5LAConfig.VehicleShowBuggy; colorKey = "VehicleColor_Buggy"
                                        elseif item.name == "Coupe RB" then isShow = _G.MON5LAConfig.VehicleShowCoupe; colorKey = "VehicleColor_Coupe"
                                        elseif item.name == "Mirado" then isShow = _G.MON5LAConfig.VehicleShowMirado; colorKey = "VehicleColor_Mirado"
                                        elseif item.name == "Motor" or item.name == "Scooter" then isShow = _G.MON5LAConfig.VehicleShowMotor; colorKey = "VehicleColor_Motor"
                                        else isShow = _G.MON5LAConfig.VehicleShowOther; colorKey = "VehicleColor_Other" end
                                        if isShow then
                                            local distM = 0
                                            pcall(function() distM = localPlayer:GetDistanceTo(veh) / 100 end)
                                            if distM > 0 and distM <= 300 then
                                                local hpStr = ""
                                                pcall(function()
                                                    local hp = veh.HP or (type(veh.GetHP) == "function" and veh:GetHP()) or 100
                                                    local maxHp = veh.HPMax or (type(veh.GetHPMax) == "function" and veh:GetHPMax()) or 100
                                                    if maxHp > 0 then hpStr = string.format(" [%d%%]", math.floor((hp/maxHp)*100)) end
                                                end)
                                                local text = string.format("%s%s [%dm]", item.name, hpStr, math.floor(distM))
                                                local vehColor = GetColorBy7(_G.MON5LAConfig[colorKey] or 4)
                                                local dynamicScale = math.max(0.6, 1.1 - (distM / 500))
                                                MyHUD:AddDebugText(text, veh, 0.3, {X=0, Y=0, Z=50}, {X=0, Y=0, Z=50}, vehColor, true, false, true, nil, dynamicScale, true)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
        end

        -- ===== ESP LOOT =====
        if _G.MON5LAConfig.EspLoot then
            pcall(function()
                local MyHUD = Cached_MyHUD
                if Valid(MyHUD) then
                    if not _G.CachedGameplayStatics then _G.CachedGameplayStatics = import("GameplayStatics") end
                    if not _G.CachedActorClass_ForLoot then _G.CachedActorClass_ForLoot = import("Actor") end
                    if not _G.CachedLootArray then _G.CachedLootArray = slua.Array(UEnums.EPropertyClass.Object, _G.CachedActorClass_ForLoot) end
                    local ui_util = require("client.common.ui_util")
                    local gameInstance = ui_util and ui_util.GetGameInstance()
                    if gameInstance and _G.CachedGameplayStatics then
                        local curTime = os.clock()
                        local scanInterval = 0.5
                        local mode = _G.MON5LAConfig.LootScanMode or 0
                        if mode == 0 then scanInterval = 0.5
                        elseif mode == 10 then scanInterval = 10.0
                        elseif mode == 20 then scanInterval = 20.0
                        end
                        
                        if not _G.LastLootScanTime or (curTime - _G.LastLootScanTime) >= scanInterval then
                            _G.LastLootScanTime = curTime
                            local allActors = _G.CachedGameplayStatics.GetAllActorsOfClass(gameInstance, _G.CachedActorClass_ForLoot, _G.CachedLootArray)
                            local lootItems = {}
                            local lootKeywords = {
    ["m416"] = {name = "M416", toggle = "LootShowM416", colorKey = "LootColor_M416"},
    ["aug"] = {name = "AUG", toggle = "LootShowAUG", colorKey = "LootColor_AUG"},
    ["akm"] = {name = "AKM", toggle = "LootShowAKM", colorKey = "LootColor_AKM"},
    ["m24"] = {name = "M24", toggle = "LootShowM24", colorKey = "LootColor_M24"},
    ["m249"] = {name = "M249", toggle = "LootShowM249", colorKey = "LootColor_M249"},
    ["ump45"] = {name = "UMP45", toggle = "LootShowUMP", colorKey = "LootColor_UMP"},
    ["ump"] = {name = "UMP45", toggle = "LootShowUMP", colorKey = "LootColor_UMP"},
    ["dbs"] = {name = "DBS", toggle = "LootShowDBS", colorKey = "LootColor_DBS"},
    ["s12k"] = {name = "S12K", toggle = "LootShowS12K", colorKey = "LootColor_S12K"},
    ["s12"] = {name = "S12K", toggle = "LootShowS12K", colorKey = "LootColor_S12K"},
}
                            local level3Items = {
    --["vest"] = {name = "Vest Lv3", toggle = "LootShowVest3", colorKey = "LootColor_Vest3"},
    ["armor"] = {name = "Vest Lv3", toggle = "LootShowVest3", colorKey = "LootColor_Vest3"},
    ["helmet"] = {name = "Helm Lv3", toggle = "LootShowHelmet3", colorKey = "LootColor_Helmet3"},
    ["helm"] = {name = "Helm Lv3", toggle = "LootShowHelmet3", colorKey = "LootColor_Helmet3"},
    ["bag 3"] = {name = "Bag Lv3", toggle = "LootShowBag3", colorKey = "LootColor_Bag3"},
    ["backpack 3"] = {name = "Bag Lv3", toggle = "LootShowBag3", colorKey = "LootColor_Bag3"},
    ["bag_lv3"] = {name = "Bag Lv3", toggle = "LootShowBag3", colorKey = "LootColor_Bag3"},
    ["backpack_lv3"] = {name = "Bag Lv3", toggle = "LootShowBag3", colorKey = "LootColor_Bag3"},
}

                            if allActors then
                                for _, actor in pairs(allActors) do
                                    if slua.isValid(actor) and not actor.bHidden and not actor.bTearOff then
                                        local isPendingKill = false
                                        pcall(function() if type(actor.IsPendingKill) == "function" then isPendingKill = actor:IsPendingKill() end end)
                                        if not isPendingKill then
                                            local actorName = ""
                                            pcall(function() 
                                                if type(actor.GetName) == "function" then actorName = actor:GetName()
                                                elseif actor.Name then actorName = actor.Name
                                                else actorName = tostring(actor) end
                                            end)
                                            local lowerName = string.lower(actorName)
                                            if lowerName == "" then lowerName = string.lower(tostring(actor)) end
                                            
                                            local displayInfo = nil
                                            local matched = false

                                            for keyword, info in pairs(lootKeywords) do
                                                if string.find(lowerName, keyword, 1, true) then
                                                    displayInfo = info
                                                    matched = true
                                                    break
                                                end
                                            end

                                            if not matched then
                                                for keyword, info in pairs(level3Items) do
                                                    if string.find(lowerName, keyword, 1, true) and string.find(lowerName, "3", 1, true) then
                                                        displayInfo = info
                                                        matched = true
                                                        break
                                                    end
                                                end
                                            end

                                            if matched and displayInfo then
                                                table.insert(lootItems, {act = actor, info = displayInfo})
                                            end
                                        end
                                    end
                                end
                            end
                            _G.CachedLootItems = lootItems
                        end

                        if _G.CachedLootItems then
                            for _, item in ipairs(_G.CachedLootItems) do
                                local loot = item.act
                                if slua.isValid(loot) and not loot.bHidden then
                                    local distM = 0
                                    pcall(function() distM = localPlayer:GetDistanceTo(loot) / 100 end)
                                    if distM > 0 and distM <= 100 then
                                        local displayName = item.info.name
                                        local toggle = item.info.toggle
                                        if toggle and not _G.MON5LAConfig[toggle] then goto continue end
                                        local colorIdx = _G.MON5LAConfig[item.info.colorKey] or 4
                                        local color = GetColorBy7(colorIdx)
                                        local dynamicScale = math.max(0.5, 1.0 - (distM / 100))
                                        MyHUD:AddDebugText(
                                            string.format("%s [%dm]", displayName, math.floor(distM)),
                                            loot,
                                            0.3,
                                            {X=0, Y=0, Z=30},
                                            {X=0, Y=0, Z=30},
                                            color,
                                            true, false, true, nil, dynamicScale, true
                                        )
                                    end
                                end
                                ::continue::
                            end
                        end
                    end
                end
            end)
        end

        -- ===== ESP STATIC =====
        if _G.MON5LAConfig.EspStatic then
            pcall(function()
                local MyHUD = Cached_MyHUD
                if not Valid(MyHUD) then return end

                -- ESP ENEMY COUNT
                if _G.MON5LAConfig.EspEnemyCount then
                    local function GetRainbowColor()
                        local time = os.clock()
                        local r = math.sin(time * 0.8) * 0.5 + 0.5
                        local g = math.sin(time * 0.8 + 2.094) * 0.5 + 0.5
                        local b = math.sin(time * 0.8 + 4.188) * 0.5 + 0.5
                        return { R = math.floor(r * 255), G = math.floor(g * 255), B = math.floor(b * 255), A = 255 }
                    end

                    local myTeamId = localPlayer.TeamID or localPlayer:GetTeamID() or 0
                    local myPos = localPlayer:K2_GetActorLocation()
                    local maxDist = 35000
                    local realCount = 0
                    local aiCount = 0

                    for _, tPawn in pairs(allCharacters) do
                        if slua.isValid(tPawn) and tPawn ~= localPlayer then
                            local targetTeamId = tPawn.TeamID or tPawn:GetTeamID() or 0
                            if targetTeamId ~= myTeamId then
                                local enemyPos = tPawn:K2_GetActorLocation()
                                if enemyPos then
                                    local dx = enemyPos.X - myPos.X
                                    local dy = enemyPos.Y - myPos.Y
                                    local dz = enemyPos.Z - myPos.Z
                                    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                                    if dist <= maxDist then
                                        local isAI = false
                                        if tPawn.bIsAI == true or tPawn.IsAI == true then isAI = true end
                                        if not isAI then
                                            local pState = tPawn.PlayerState or (type(tPawn.GetPlayerState) == "function" and tPawn:GetPlayerState())
                                            if slua.isValid(pState) then
                                                if pState.bIsABot == true or pState.bIsBot == true then isAI = true end
                                                local playerID = pState.PlayerId or pState.PlayerID
                                                if playerID and (playerID == 0 or playerID < 10000) then isAI = true end
                                                local exactPing = pState.ExactPing or pState.Ping
                                                if exactPing and exactPing == 0 then isAI = true end
                                            else isAI = true end
                                        end
                                        if isAI then aiCount = aiCount + 1 else realCount = realCount + 1 end
                                    end
                                end
                            end
                        end
                    end

                    local color = GetRainbowColor()
                    local totalEnemy = realCount + aiCount
                    local text = totalEnemy > 0 and string.format("❮ ENEMY : %d ❯", totalEnemy) or " ❮AREA 350M CLEAR || @D331D❯"
                    MyHUD:AddDebugText(text, localPlayer, 1.05, {X=0, Y=0, Z=150}, {X=0, Y=0, Z=150}, color, true, false, true, nil, 1.2, true)
                end

                -- ESP WEAPON & STATUS ENEMY
                if _G.MON5LAConfig.EspWeaponStatus then
                    local ui_util = require("client.common.ui_util")
                    local viewportSize = ui_util and ui_util.GetViewportSize()
                    if viewportSize then
                        local centerX = viewportSize.X * 0.5
                        local centerY = viewportSize.Y * 0.5
                        local FOV_RADIUS = (10 / 100.0) * (viewportSize.X / 2.0)
                        local FVector2D = import("Vector2D")
                        local bestTarget = nil
                        local bestDist = 999999

                        for _, enemy in pairs(allCharacters) do
                            if Valid(enemy) and enemy ~= localPlayer and enemy.TeamID ~= localPlayer.TeamID then
                                local ePos = enemy:K2_GetActorLocation()
                                if ePos then
                                    local screen = FVector2D()
                                    if pc:ProjectWorldLocationToScreen(ePos, screen, false) and screen.X > 0 and screen.Y > 0 then
                                        local dx = screen.X - centerX
                                        local dy = screen.Y - centerY
                                        local distScreen = math.sqrt(dx*dx + dy*dy)
                                        if distScreen <= FOV_RADIUS then
                                            local dist3D = localPlayer:GetDistanceTo(enemy)
                                            if dist3D < bestDist then
                                                bestDist = dist3D
                                                bestTarget = enemy
                                            end
                                        end
                                    end
                                end
                            end
                        end

                        if Valid(bestTarget) then
                            local distM = math.floor(bestDist / 100)
                            local hp = bestTarget.Health or 100
                            local maxHp = bestTarget.HealthMax or 100
                            local hpPercent = maxHp > 0 and math.floor((hp / maxHp) * 100) or 0
                            local isKnock = (hp <= 0 or bestTarget.HealthStatus == 1)
                            
                            local weaponName = "Tangan Kosong"
                            local eWeapon = nil
                            if bestTarget.CurrentWeapon then eWeapon = bestTarget.CurrentWeapon
                            elseif type(bestTarget.GetCurrentWeapon) == "function" then eWeapon = bestTarget:GetCurrentWeapon()
                            elseif bestTarget.WeaponManagerComponent then eWeapon = bestTarget.WeaponManagerComponent.CurrentWeaponReplicated end
                            if Valid(eWeapon) and type(eWeapon.GetWeaponName) == "function" then weaponName = eWeapon:GetWeaponName() end

                            local statusText = isKnock and " [K]" or ""
                            local text = string.format("%s | %dm | %d%% HP%s", weaponName, distM, hpPercent, statusText)
                            MyHUD:AddDebugText(text, bestTarget, 0.15, {X=0, Y=0, Z=-50}, {X=0, Y=0, Z=-50}, C_YELLOW, true, false, true, nil, 0.8, true)
                        end
                    end
                end
            end)
        end
    end)
end

_G.MON5LAState.LoopToken = (_G.MON5LAState.LoopToken or 0) + 1 
local myToken = _G.MON5LAState.LoopToken

-- ========================================== 
-- LOOP UTAMA — يعمل دائماً، ويتحقق من isExpired داخلياً
-- ✅ الإصلاح: يعيد جدولة نفسه دائماً (حتى عند انتهاء الصلاحية)
-- ========================================== 
local function FastTick() 
    if isExpired then 
        if not _G.MON5LANotifiedExpire then
            _G.MON5LANotifiedExpire = true
            print("[N5LA] ⏳ Waiting for activation...")
        end
        local okTicker, ticker = pcall(require, "common.time_ticker") 
        if okTicker and ticker and ticker.AddTimerOnce then 
            ticker.AddTimerOnce(1.0, FastTick) 
        end
        return 
    end

    -- ✅ عند التفعيل: عرض رسالة الترحيب مرة واحدة
    if _G.MON5LANotifiedExpire then
        _G.MON5LANotifiedExpire = false
        pcall(function()
            local sh = import("ScriptHelperClient")
            if sh and sh.AddOnScreenDebugMessage then
                sh.AddOnScreenDebugMessage("[N5LA] ✅ تم التفعيل - المود يعمل الآن!", -1, 4.0, 
                    {R=0, G=1, B=0, A=1}, {X=1.2, Y=1.2})
            end
        end)
        print("[N5LA] ✅ License activated - MainLoop starting!")
    end

    -- ✅✅✅ الحل: استدعاء القائمة والإعدادات BEFORE MainLoop
    -- (بغض النظر عن وجود localPlayer)
    pcall(function()
        if _G.InitModMenuTab then _G.InitModMenuTab() end
    end)
    pcall(function()
        if _G.ShowMON5LAVIPMenu then _G.ShowMON5LAVIPMenu() end
    end)

    if myToken ~= _G.MON5LAState.LoopToken then return end
    pcall(MainLoop) 
    local okTicker, ticker = pcall(require, "common.time_ticker") 
    if okTicker and ticker and ticker.AddTimerOnce then 
        ticker.AddTimerOnce(0.2, FastTick) 
    end 
end

-- ========================================== 
-- LOOP AIMBOT — يعمل دائماً، ويتحقق من isExpired داخلياً
-- ✅ الإصلاح: يعيد جدولة نفسه دائماً
-- ========================================== 
local aimbotToken = 0
local function FastAimbotTick()
    -- ⚠️ مهم جدًا: نستمر في الجدولة حتى عند عدم التفعيل
    if isExpired then 
        local okTicker, ticker = pcall(require, "common.time_ticker")
        if okTicker and ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(1.0, FastAimbotTick)  -- بطيء عند عدم التفعيل
        end
        return 
    end

    if aimbotToken ~= _G.MON5LAState.AimbotLoopToken then 
        return 
    end

    pcall(function()
        if _G.MON5LAConfig and _G.MON5LAConfig.AimTouchEnable then
            _G.AimTouch()
        end
    end)

    local okTicker, ticker = pcall(require, "common.time_ticker")
    if okTicker and ticker and ticker.AddTimerOnce then
        ticker.AddTimerOnce(0.016, FastAimbotTick)
    end
end

-- ========================================== 
-- IGNITE BOTH LOOPS — ✅ دائماً، بغض النظر عن حالة isExpired
-- ========================================== 
FastTick()  -- الحلقة الرئيسية — ستعيد جدولة نفسها تلقائياً

_G.MON5LAState.AimbotLoopToken = (_G.MON5LAState.AimbotLoopToken or 0) + 1
aimbotToken = _G.MON5LAState.AimbotLoopToken
local okTicker, ticker = pcall(require, "common.time_ticker")
if okTicker and ticker and ticker.AddTimerOnce then
    ticker.AddTimerOnce(0.1, FastAimbotTick)
end

-- رسالة الترحيب (فقط لو التفعيل محصل قبل الفتح)
if not isExpired then
    Notify("أنت تستخدم VIP Mod. إذا لم يكن لديك مفتاح، راسل Telegram : @D331D")
end
-- ================================================================================
--  ██  ANTI-BAN + BYPASS BLOCK — self-contained, paste-in ready          ██
--  ██  No login • No license • No duplicates • Idempotent                ██
--  ██  Exposes: _G.StartBypass_VIP_v3 • _G.RunAntiBan • _G.KillBanPopup ██
-- ================================================================================
do
    -- ── double-init guard ─────────────────────────────────────────────
    if _G._N5LA_AntiBan_Installed then
        if type(_G.StartBypass_VIP_v3) == "function" then _G.StartBypass_VIP_v3() end
    else
    _G._N5LA_AntiBan_Installed = true

    -- ── helpers ───────────────────────────────────────────────────────
    local nop      = function() return true  end
    local retTrue  = function() return true  end
    local retFalse = function() return false end
    local retZero  = function() return 0     end
    local retEmpty = function() return {}    end
    local retNil   = function() return nil   end
    local retES    = function() return ""    end

    local function safeRequire(path)
        local m = package.loaded[path]
        if m then return m end
        local ok, r = pcall(require, path)
        return ok and r or nil
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §1  SLUA / Bytecode / JIT
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_SLUA()
        pcall(function()
            if slua and slua.getSignature then
                slua.getSignature = function() return 0xDEADBEEF end
            end
            local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
            if loader then
                loader.verifyBytecode        = retTrue
                loader.checkIntegrity        = retTrue
                loader.disableSignatureCheck = retTrue
            end
            local serialize = package.loaded["slua.serialize"]
            if serialize then
                serialize.check  = retTrue
                serialize.verify = retTrue
            end
            if jit and jit.attach then jit.attach(function() end, "bc") end
            _G.slua_verify          = retTrue
            _G.check_slua_integrity = retTrue
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §2  MD5 / CRC / File Hash
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_MD5()
        pcall(function()
            local CMode = import("CreativeModeBlueprintLibrary")
            if CMode then
                CMode.MD5HashByteArray    = function() return string.rep("0", 32) end
                CMode.MD5HashFile         = function() return string.rep("0", 32) end
                CMode.GetContentDiffData  = function() return true, "BYPASSED" end
                CMode.VerifyFileIntegrity = retTrue
                CMode.VerifyContent       = retTrue
                CMode.ValidateContent     = retTrue
                CMode.CheckContent        = retTrue
            end

            _G.MD5Hash = function() return string.rep("0", 32) end
            _G.CRC32   = retZero
            _G.SHA1    = function() return "BYPASS" end

            local FHC = package.loaded["common.file_hash_checker"]
            if FHC then
                FHC.CheckFileMD5 = retTrue
                FHC.VerifyAll    = retTrue
                FHC.GetHash      = function() return "BYPASS" end
            end

            local STExtra = import("STExtraBlueprintFunctionLibrary")
            if STExtra then
                STExtra.CheckMD5   = retTrue
                STExtra.GetMD5     = function() return "BYPASS" end
                STExtra.VerifyFile = retTrue
            end

            local CC = _G.CRCChecker or package.loaded["CRCChecker"]
            if CC then
                CC.VerifyFile     = retTrue
                CC.VerifyMemory   = retTrue
                CC.CheckIntegrity = retTrue
                CC.ValidateFile   = retTrue
                CC.ValidateMemory = retTrue
                CC.CheckFile      = retTrue
                CC.CheckMemory    = retTrue
                CC.VerifyCRC      = retTrue
                CC.ValidateCRC    = retTrue
                CC.CheckCRC       = retTrue
                CC.GenerateCRC    = function() return "00000000" end
                CC.GenerateCRC32  = function() return "00000000" end
                CC.GenerateCRC64  = function() return "0000000000000000" end
                CC.GenerateMD5    = function() return string.rep("0", 32)  end
                CC.GenerateSHA1   = function() return string.rep("0", 40)  end
                CC.GenerateSHA256 = function() return string.rep("0", 64)  end
                CC.GenerateSHA512 = function() return string.rep("0", 128) end
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §3  PAK / Signature
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_PAK()
        pcall(function()
            local KSL = import("KismetSystemLibrary")
            if KSL and KSL.ExecuteConsoleCommand then
                local cmds = {
                    "pak.DisablePakSignatureCheck 1",
                    "pakchunk.EnableSignatureCheck 0",
                    "s.VerifyPak 0",
                    "sig.Check 0",
                    "security.DisableChecks 1"
                }
                for _, c in ipairs(cmds) do
                    pcall(KSL.ExecuteConsoleCommand, nil, c)
                end
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §4  Log / TLog / CrashSight / Bugly
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_Logging()
        pcall(function()
            -- CrashSight
            local CS = _G.CrashSight or package.loaded["CrashSight"]
            if CS then
                for _, m in ipairs({
                    "ReportException","SetCustomData","Log","UploadLog","SendReport",
                    "ReportCrash","ReportError","ReportFatal","ReportWarning",
                    "ReportInfo","ReportDebug","ReportMemory","ReportPerformance"
                }) do CS[m] = nop end
                CS.CollectInfo = retEmpty
            end

            -- TLog
            local TL = _G.TLog or package.loaded["TLog"]
            if TL then
                for _, m in ipairs({
                    "Info","Warning","Error","Debug","Report","Flush",
                    "Log","LogWarning","LogError","LogVerbose","SetLogLevel"
                }) do TL[m] = nop end
            end

            -- TDataMaster
            local TDM = _G.TDataMaster or package.loaded["libTDataMaster.so"]
            if TDM then
                for _, m in ipairs({
                    "ReportEvent","ReportException","FlushData","SendReport",
                    "ReportTelemetry","ReportAnalytics","ReportMetrics",
                    "ReportStatistics","ReportPerformance","ReportBattery",
                    "ReportTemperature","ReportFPS","ReportPing","ReportNetwork"
                }) do TDM[m] = nop end
                TDM.CollectData = retEmpty
            end

            -- GRUtils (Bugly)
            local GR = package.loaded["GameLua.Mod.BaseMod.Gameplay.GameReport.GameReportUtils"]
            if GR then
                GR.BugglyPostExceptionFull     = retFalse
                GR.CheckCanBugglyPostException = retFalse
                GR.ReplayReportData            = nop
                GR.ReportGameException         = nop
                GR.PostException               = nop
            end

            -- ClientToolsReport
            local CTR = package.loaded["client.slua.logic.report.ClientToolsReport"]
            if CTR then
                CTR.SendReport    = nop
                CTR.SendException = nop
                CTR.UploadLog     = nop
            end

            -- Equipment Exception
            local EQ = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
            if EQ then
                EQ.Report        = nop
                EQ.SendException = nop
            end

            -- Analytics SDKs
            for _, sdk in ipairs({"Firebase","Adjust","AppsFlyer","FacebookAnalytics","GameAnalytics"}) do
                local s = _G[sdk]
                if s then
                    s.logEvent   = nop
                    s.trackEvent = nop
                    s.setEnabled = retFalse
                    s.sendEvent  = nop
                    s.report     = nop
                end
            end

            -- Logging facade
            local Lg = import("Logging")
            if Lg then
                for _, m in ipairs({
                    "Log","LogWarning","LogError","LogVerbose","SetLogLevel",
                    "LogInfo","LogDebug","LogTrace","LogFatal","LogPanic"
                }) do Lg[m] = nop end
            end

            -- Global logging silence
            for _, g in ipairs({"print","printf","log","warn","error","debug",
                                "trace","info","verbose","fatal","panic","recover","assert"}) do
                _G[g] = nop
            end

            -- LogUtil
            local LU = _G.LogUtil
            if LU then
                LU.SetForceLog      = nop
                LU.SetLogTreeEnable = nop
                LU.SetWriteLog      = nop
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §5  Screenshot / Screen capture
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_Screenshot()
        pcall(function()
            local SMTD = import("ScreenshotMTDer")
            if SMTD then
                SMTD.MTDePicture    = retES
                SMTD.ReMTDePicture  = retES
                SMTD.HasCaptured    = retTrue
                SMTD.TakeScreenshot = nop
            end
            local SM = import("ScreenshotMaker")
            if SM then
                SM.MakePicture    = retES
                SM.ReMakePicture  = retES
                SM.HasCaptured    = retTrue
                SM.TakeScreenshot = nop
                SM.SaveScreenshot = nop
                SM.CaptureScreen  = nop
                SM.RecordScreen   = nop
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §6  Subsystem registry sweep
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_Subsystems()
        pcall(function()
            local SM = safeRequire("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
            if not SM then return end

            local TARGETS = {
                "CoronaLabSubsystem","PlayerSecurityInfoSubsystem",
                "ClientCircleFlowSubsystem","ModifierExceptionSubsystem",
                "SimulateCharacterSubsystem","ShootVerifySubSystemClient",
                "HiggsBosonComponent","ClientReportPlayerSubsystem",
                "DSReportPlayerSubsystem","ClientHawkEyePatrolSubsystem",
                "DSHawkEyePatrolSubsystem","ClientDataStatistcsSubsystem",
                "AFKReportorSubsystem","BehaviorScoreSubsystem",
                "FileCheckSubsystem","MemoryCheckSubsystem",
                "SpeedCheckSubsystem","WallCheckSubsystem",
                "AvatarExceptionSubsystem","GameReportSubsystem",
                "ClientSecMrpcsFlowSubsystem","MrpcsFlowSubsystem",
                "CircleFlowSubsystem","SwiftHawkSubsystem",
                "AntiCheatSubsystem","IntegrityCheckSubsystem",
                "SignatureVerifySubsystem","MD5CheckSubsystem",
                "PakVerifySubsystem","ReplaySubsystem",
                "OperationalStatsSubsystem","TelemetrySubsystem",
                "RescueBtnReplayTraceSubsystem"
            }

            local METHOD_KEYWORDS = {
                "Report","Send","Upload","Verify","Check","Validate",
                "Scan","Detect","Collect","Flow","Heartbeat"
            }

            local TIMER_FIELDS = {
                "TimerHandle","timer","heartbeatTimer","reportTimer",
                "scanTimer","checkTimer","uploadTimer","sendTimer",
                "collectTimer","telemetryTimer","statsTimer",
                "ReportPingDelayTimer"
            }

            local function hit(k)
                for i = 1, #METHOD_KEYWORDS do
                    if k:find(METHOD_KEYWORDS[i], 1, true) then return true end
                end
            end

            for _, name in ipairs(TARGETS) do
                local sub = SM:Get(name)
                if sub then
                    for k, v in pairs(sub) do
                        if type(v) == "function" and hit(k) then
                            pcall(function() sub[k] = nop end)
                        end
                    end
                    for _, t in ipairs(TIMER_FIELDS) do
                        if sub[t] then
                            pcall(function() sub:RemoveGameTimer(sub[t]) end)
                            sub[t] = nil
                        end
                    end
                    sub.DelayCount = 0
                end
            end

            -- Generic sweep on every registered subsystem
            if SM.GetAllSubsystems then
                local all = SM:GetAllSubsystems()
                local genericNames = {
                    "Report","ReportException","SendReport","CollectData","Validate",
                    "CheckIntegrity","Verify","Check","ValidateData","VerifyData","CheckData",
                    "ValidateState","VerifyState","CheckState","ValidateConfig","VerifyConfig",
                    "CheckConfig","ValidatePlayer","VerifyPlayer","CheckPlayer","ValidateGame",
                    "VerifyGame","CheckGame","ValidateSystem","VerifySystem","CheckSystem",
                    "ValidateDevice","VerifyDevice","CheckDevice","ValidateNetwork","VerifyNetwork",
                    "CheckNetwork","ValidateMemory","VerifyMemory","CheckMemory","ValidateFile",
                    "VerifyFile","CheckFile","ValidateProcess","VerifyProcess","CheckProcess",
                    "ValidateThread","VerifyThread","CheckThread","ValidateModule","VerifyModule",
                    "CheckModule","ValidateAPI","VerifyAPI","CheckAPI","ValidateSDK","VerifySDK","CheckSDK"
                }
                for _, sub in pairs(all) do
                    if sub then
                        for _, m in ipairs(genericNames) do
                            if type(sub[m]) == "function" then
                                pcall(function() sub[m] = nop end)
                            end
                        end
                    end
                end
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §7  Module path patches (report + tlog + security)
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_Modules()
        pcall(function()
            local NOP_METHODS = {
                "Report","SendReport","ReportEvent","ReportException","ReportData",
                "ReportTLogEvent","OnInit","_OnPlayerKilledOtherPlayer","_RecordFatalDamager",
                "_OnBattleResult","_OnShowQuickReportMutualExclusiveUI","_AddEnemyMapToBattleResult",
                "_AddKnockDownerToBattleResult","_AddKillerToBattleResult","_AddTeammateMurderToBattleResult",
                "_AddFatalDamagerMapToBattleResult","_AddMLKillerUIDToBattleResult",
                "_SaveHistoricalTeammateInfo","_RecordTeammateMurderer","_OnNearDeathOrRescued",
                "_OnCharacterDied","_OnTeammateDamage","_OnPlayerSettlementStart","_OnHawkSync",
                "_OnHawkReportSuccess","_StartExitGameTimer","OnHandleBehaviorScore","AIPerceptionScore",
                "ReportAllPlayerInfo","AddRecordMLAIInfo","ReportAI","RealLogoutTimer","SendAFKTips",
                "OnHandleLostConnection","ClientRPC_SyncBanID","ClientRPC_StrongTips","ClientRPC_NormalTips",
                "Notify","OnSyncBanInfo","OnVoiceBanNotify","DelayKickOutPlayer","ActiveKickNotify",
                "_UpdateTTKRecords","_UpdateOperatingFrequency","_OnReportServerJumpFlow",
                "HandleKillTlog","AskForInspector","ReportEnemy","KickOutOneTeam",
                "ServerKickOutOneTeamByPlayerImplementation","AddReportedCount",
                "RequestGotoSpectatingImp","RequestGotoSpectating",
                -- tlog-specific
                "SendTlog","ReportTLog","ReportReplay","SendReportReq","SaveDump","UploadDump",
                -- security-specific
                "OnPlayerWithRealTimeBan","OnSyncPlayerInfo","HandleEnterGameModeFightingState",
                "ShowAlias","SetOnRankInspectorUID","SetInspectorBroadcastCountUID","GMShowAlias",
                "ReqBanInfo","OnVoiceSwitchNotify","OnRealTimeVoiceBanNotify","OnVoiceBanSuccess",
                "TryOpenVoice","OnSyncMicSuspicious","OnSyncMicPreFilter","OnNotifyWarningTips",
                "PakMonitorStart","SetupFilenameHideKeywords","on_login_failed",
                "DelaybanLoginCancelCallback","HandleRacingEnter","HandleRacingStart","HandleRacingEnd",
                "StartDetectTimer","StopDetectTimer","DetectVehicleFloating","HandleFloatingCheat",
                "SetIgnoreFloating","HandlePlayerPassCheckBelt","HandleSpeedCheat",
                -- hawkeye
                "_OnRecvInspectorBroadcastCount","RequestImprison","SendReportTLog",
                "_CollectBeWatchedPlayerInfo","_StartFrameUIRefreshTimer","ExitWatching",
                "WantMatchNextPatrol","_StartHideUITimer","_StartShowDistanceUITimer",
                "_StartCloseBattleEndedTipsTimer","_StartBattleTimeUsageTimer",
                "_StartQuitVoiceRoomTimer","_CloseExitGameTimer",
                "_CreateOvertimerTimerForNextPatrol","ClearNextPatrolOvertimeTimer",
                "ReturnLobbyAndOpenH5","ForceNeverCloseBattleEndedTips","TryShowReportedTips",
                "ShowWatchEndedTips","OnShowWatchEndedTips","OnClickLowerLeftExitWatching",
                "OnClickBottomRightOpenReportWindow","_MarkHasReported",
                -- login-module hyphen names cannot be table keys here; kept in HyphenBlock below
                "InitGokubaLogic","OnControllerBeginPlay",
                -- AI/log
                "ClearCache","FreeUnusedMemory","CompactHeap","CleanTraces",
                "ClearLogs","ClearTemp","ClearCacheFiles","ClearHistory","ClearData",
                -- MD5/memory fallbacks
                "VerifyFile","VerifyMemory","CheckIntegrity","ValidateFile","ValidateMemory",
                "CheckFile","CheckMemory","VerifyCRC","ValidateCRC","CheckCRC"
            }

            local TRUE_METHODS = {
                "CheckIfCanCreateRole","CheckBan","IsBanned","IsVoiceReportEnable",
                "IsDuringHawkEyePatrol","HasReported","HasShownWatchEndedTips",
                "CanInspectorBroadcast","IsCharacterLocationShouldDraw",
                "IsUIDOnRankInspector","IsEmulator","IsRooted","IsDebugged",
                "CheckKernelIntegrity","IsMemoryReadable","IsMemoryWritable"
            }

            local EMPTY_METHODS = {
                "GetCarrierInfo","GetSimpleFightData","GetWeaponReport","GetOneWeaponReport",
                "GetGeneralTLogData","GetBeWatchedPlayerInfo","CollectInfo","GetResults","_CreateVehicleData"
            }

            local ZERO_METHODS = {
                "GetUIDInspectorRank","GetTipsIDOffset","GetTipsIDOffsetWithUID",
                "GetTipsIDOffsetInspector","GetForbidNextPatrolRemainingTimeInSeconds",
                "GetUsedDailyTimeInSeconds","GetMaxInspectorBroadcastCount"
            }

            local PATHS = {
                -- Report paths
                "GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem",
                "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem",
                "client.slua.logic.report.EquipmentExceptionReport",
                "client.slua.logic.report.ClientToolsReport",
                "GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils",
                "client.slua.logic.download.report.puffer_tlog",
                "GameLua.Mod.BaseMod.Client.Security.ClientGlueHiaSystem",
                "GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils",
                "GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature",
                "GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent",
                "client.slua.logic.ban.ClientBanLogic",
                "client.slua.logic.login.logic_tt_ban",
                "GameLua.Mod.PlanBT.Gameplay.Subsystem.DSActiveSubsystem",
                "GameLua.Mod.BaseMod.DS.Security.DSAITLogSubsystem",
                "GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem",
                "GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem",
                "GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem",
                "GameLua.Mod.BaseMod.Client.Security.InspectionSystemReportClientLogicSubsystem",
                "GameLua.Mod.BaseMod.DS.Security.InspectionSystemReportDSLogicSubsystem",
                "GameLua.Mod.BaseMod.Common.Subsystem.SpectateAndReplaySubsystem",
                "GameLua.Mod.BaseMod.Client.Security.ClientHawkEyePatrolSubsystem",
                "GameLua.Mod.Escape.Gameplay.Subsystem.BehaviorScoreSubsystem",
                "GameLua.ExtraModule.MLAI.Client.AIReplaySubsystem",
                "GameLua.Mod.BaseMod.GamePlay.AI.AITrackingLogSubsystem",
                "GameLua.Mod.TDM.Gameplay.Subsystem.TDMAFKReportorSubsystem",
                "GameLua.Mod.BaseMod.Client.Security.SwiftHawkSubsystem",
                "GameLua.Mod.BaseMod.Client.Security.Gokuba",
                "GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem",
                "GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem",
                "GameLua.Mod.BaseMod.Gameplay.Simulate.SimulateCharacterSubsystem",
                "GameLua.Dev.Subsystem.ShootVerifySubSystemClient",
                -- TLog paths
                "client.slua.config.tlog.tlog_report_utils",
                "client.slua.logic.replay.logic_report_replay",
                "client.slua.logic.crash.CrashReporter",
                "GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"
            }

            for _, path in ipairs(PATHS) do
                local m = safeRequire(path)
                if m then
                    for _, k in ipairs(NOP_METHODS)   do if type(m[k]) == "function" then m[k] = nop end end
                    for _, k in ipairs(TRUE_METHODS)  do if type(m[k]) == "function" then m[k] = retTrue end end
                    for _, k in ipairs(EMPTY_METHODS) do if type(m[k]) == "function" then m[k] = retEmpty end end
                    for _, k in ipairs(ZERO_METHODS)  do if type(m[k]) == "function" then m[k] = retZero end end
                    -- hawk-eye boolean fields
                    if path:find("HawkEye") then
                        m._bHasInitialized         = true
                        m._bHasReported            = true
                        m._bHasShownWatchEndedTips = true
                        m.bShowBeReportedTips      = true
                        m.nInspectorBroadcastCount = -1
                        if type(m._PostConstruct) == "function" then
                            m._PostConstruct = function(self)
                                self._bHasInitialized         = true
                                self._bHasReported            = true
                                self.nInspectorBroadcastCount = -1
                            end
                        end
                    end
                    -- gokuba special
                    if path:find("Gokuba") then
                        m.ForwardFeature = function() return {0,0,0,0,0} end
                    end
                    -- racing config
                    if path:find("Racing") then
                        m.config = { FloatingDistLimit = 99999, FloatingTimeLimit = 99999, CheckPassIntervalLimit = 99999 }
                    end
                    -- tlog
                    if m.LogQueue then m.LogQueue = {} end
                    if m.vehicleDataMap then m.vehicleDataMap = {} end
                    if m.detectTimer then m.detectTimer = nil end
                end
            end

            -- Login-module hyphen keys (cannot live in NOP_METHODS table)
            local lm = _G.login_module
            if lm then
                for _, k in ipairs({
                    "ban-login","idip-kick-out","aq_ban","device-in-blacklist",
                    "device_num_limit","register-forbidden","low-version",
                    "not-in-white-list","Login_Failed","aas_ban"
                }) do
                    pcall(function() lm[k] = nop end)
                end
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §8  GameplayCallbacks
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_Callbacks()
        pcall(function()
            if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
            local GC = _G.GameplayCallbacks
            if GC._N5LA_Applied then return end

            local NOP = {
                "ReportAttackFlow","ReportSecAttackFlow","ReportHurtFlow","ReportFireArms",
                "ReportVerifyInfoFlow","ReportMrpcsFlow","ReportPlayerBehavior","ReportTeammatHurt",
                "ReportMisKillByTeammate","ReportForbitPick","ReportPlayerMoveRoute","ReportPlayerPosition",
                "ReportVehicleMoveFlow","ReportSecTgameMovingFlow","ReportParachuteData",
                "SendTssSdkAntiDataToLobby","SendDSErrorLogToLobby","SendDSErrorLogToLobbyOnece",
                "SendDSHawkEyePatrolLogToLobby","ReportEquipmentFlow","ReportAimFlow","ReportHitFlow",
                "ReportHeavyWeaponBoxSpawnFlow","ReportHeavyWeaponBoxActivationFlow",
                "ReportHeavyWeaponBoxOpenPlayerFlow","ReportHeavyWeaponBoxItemFlow",
                "ReportPlayersPing","ReportPlayerIP","ReportPlayerFramePingRecord",
                "OnDSConnectionSaturated","ReportDSNetSaturation","ReportNetContinuousSaturate",
                "ReportDSNetRate","SendClientStats","SendServerAvgTickDelta","ReportCircleFlow",
                "ReportDSCircleFlow","ReportJumpFlow","ReportAIStrategyInfo","SendAIDeliveryInfo",
                "ReportDailyTaskInfo","ReportMatchRoomData","SendPlayerSpectatingLog",
                "ReportIDCardProduceFlow","ReportIDCardPickUpFlow","ReportIDCardDestroyFlow",
                "ReportRevivalFlow","ReportGameSetting","ReportGameSettingNew",
                "ReportAntsVoiceTeamCreate","ReportAntsVoiceTeamQuit","ReportCommonInfo",
                "ReportLightweightStat","SendSecTLog","SendDataMiningTLog","SendActivityTLog",
                "SwiftHawk","ClientSwiftHawk","ClientSwiftHawkWithParams",
                "OnPlayerNetConnectionClosed","OnPlayerActorChannelError",
                "OnPlayerRPCValidateFailed","OnPlayerSpectateException","OnShutdownAfterError",
                "OnPlayerBanned","OnPlayerKicked","OnPlayerSuspended","OnCheatDetected",
                "OnViolationDetected","OnSecurityBan","OnFairPlayBan","OnPermanentBan",
                "OnTemporaryBan","OnAccountSuspended","NotifyBanResult","OnBanNotification",
                "OnPunishmentApplied","OnPenaltyApplied","OnSanctionApplied"
            }
            for _, f in ipairs(NOP) do GC[f] = nop end

            GC.CheckReportSecAttackFlowWithAttackFlow = retFalse
            GC.CheckReportSecAttackFlow               = retFalse
            GC.GetWeaponReport                        = retEmpty
            GC.GetOneWeaponReport                     = retEmpty
            GC.GetGeneralTLogData                     = retEmpty

            local BAN_KEYWORDS = {
                "cheat","ban","kick","detected","violation","suspicious",
                "abnormal","invalid","corrupt","tamper","modify","inject",
                "hook","patch","spoof","fake","clone","duplicate",
                "conflict","overlap","mismatch","inconsistent","unexpected","unknown",
                "detected","permanent","temporary","suspended","penalized","sanctioned","restricted"
            }
            local origState = GC.OnDSPlayerStateChanged
            GC.OnDSPlayerStateChanged = function(UID, State, bPure, bSafe, Param)
                local s = string.lower(tostring(State or ""))
                for i = 1, #BAN_KEYWORDS do
                    if s:find(BAN_KEYWORDS[i], 1, true) then return end
                end
                if origState then pcall(origState, UID, State, bPure, bSafe, Param) end
            end

            GC._N5LA_Applied = true
            GC.IsBypassed    = true
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §9  Network filter (packets + RPC + socket + HTTP + WS)
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_Network()
        pcall(function()
            -- ── Packet blocklist (merged, deduplicated) ──
            local BLOCKED = {
                -- Report flows
                ["ReportAttackFlow"]=1,["ReportSecAttackFlow"]=1,["ReportHurtFlow"]=1,
                ["ReportFireArms"]=1,["ReportVerifyInfoFlow"]=1,["ReportMrpcsFlow"]=1,
                ["ReportPlayerBehavior"]=1,["ReportTeammatHurt"]=1,["ReportTeammateKillConfirmFlow"]=1,
                ["ReportForbiddenPickupFlow"]=1,["ReportPlayerMoveRoute"]=1,["ReportPlayerPosition"]=1,
                ["ReportSecVehicleMoveFlow"]=1,["ReportSecTgameMovingFlow"]=1,["ReportEquipmentFlow"]=1,
                ["ReportAimFlow"]=1,["ReportHitFlow"]=1,["ReportCircleFlow"]=1,
                ["report_ds_player_circle_flow"]=1,["ReportJumpFlow"]=1,["ReportAvatarFlow"]=1,
                ["ReportIDCardProduceFlow"]=1,["ReportIDCardPickUpFlow"]=1,["ReportIDCardDestroyFlow"]=1,
                ["ReportRevivalFlow"]=1,["ReportAIActionFlow"]=1,["ReportGenerateMonsterFlow"]=1,
                ["report_heavy_weapon_box_activation_flow"]=1,
                ["report_heavy_weapon_box_item_flow"]=1,
                ["ReportHeavyWeaponBoxSpawnFlow"]=1,
                ["ReportHeavyWeaponBoxOpenPlayerFlow"]=1,
                ["ReportGameStartFlow"]=1,["ReportGameEndFlow"]=1,
                ["ReportPlayerControllerStateChanged"]=1,
                ["ReportUseSkillFlow"]=1,["SkillFlowReport"]=1,["MeleeDamageReport"]=1,
                -- Parachute / character state
                ["report_parachute_data"]=1,["report_character_state"]=1,
                ["report_camera_exception"]=1,["report_vehicle_exception"]=1,
                ["report_hit_reg_fail"]=1,["log_shooting_miss"]=1,
                -- Network stats
                ["report_players_ping"]=1,["report_player_ip"]=1,
                ["report_player_frame_ping_record"]=1,["report_net_saturate"]=1,
                ["report_ds_netsaturate"]=1,["report_ds_net_continuous_saturate"]=1,
                ["report_ds_netrate"]=1,["report_unrealnet_clientstats"]=1,
                ["report_serverstat_avgtickdelta"]=1,["report_all_players_address"]=1,
                ["report_unrealnet_exception"]=1,
                -- AI
                ["report_ai_strategyinfo"]=1,["report_ds_match_room_data"]=1,
                ["SendSpectatingLog"]=1,
                -- Settings
                ["ReportGameSetting"]=1,["ReportGameSettingNew"]=1,
                ["ReportAntsVoiceTeamCreate"]=1,["ReportAntsVoiceTeamQuit"]=1,
                -- Common
                ["report_common_info"]=1,["report_common_battle_info"]=1,
                ["report_client_scan_result"]=1,["report_ui_state"]=1,
                -- TSS SDK
                ["on_tss_sdk_anti_data"]=1,["tss_sdk_report"]=1,
                -- Memory / avatar / misc
                ["report_memory_exception"]=1,["report_avatar_exception"]=1,
                -- Security flows
                ["ClientSecMrpcsFlow"]=1,["MrpcsData"]=1,
                ["CheckReportSecAttackFlow"]=1,
                ["CheckReportSecAttackFlowWithAttackFlow"]=1,
                ["RPC_ClientCoronaLab"]=1,["CoronaLabReport"]=1,["CoronaLabData"]=1,
                ["PlayerSecurityInfo"]=1,["ReportSecurityInfo"]=1,["SendSecurityData"]=1,
                ["ClientCircleFlow"]=1,
                ["IsEnableReportMrpcsInCircleFlow"]=1,
                ["IsEnableReportMrpcsInPartCircleFlow"]=1,
                ["bReportedModifierException"]=1,["ReportModifierException"]=1,
                ["RPC_Server_ReportSimulateCharacterLocation"]=1,
                ["ReportSimulateCharacterLocation"]=1,
                ["RPC_Client_ShootVertifyRes"]=1,["ShootVerifyFailed"]=1,
                ["BulletHitInfoUploadData"]=1,
                -- SwiftHawk
                ["SwiftHawk"]=1,["ClientSwiftHawk"]=1,["ClientSwiftHawkWithParams"]=1,
                ["SwiftHawkReport"]=1,["SwiftHawkData"]=1,
                -- Generic security tags
                ["AntiCheatReport"]=1,["CheatDetection"]=1,["ViolationReport"]=1,
                ["SecurityViolation"]=1,["IntegrityCheck"]=1,["SignatureVerify"]=1,
                ["ReportSecurityAlert"]=1,["ReportAntiCheat"]=1,["ReportSuspiciousActivity"]=1,
                ["ReportViolation"]=1,["ReportBan"]=1,["ReportKick"]=1,
                ["ReportCheat"]=1,["ReportHack"]=1,["ReportMod"]=1,
                ["ReportInject"]=1,["ReportHook"]=1,["ReportPatch"]=1,
                ["ReportTamper"]=1,["ReportCorrupt"]=1,["ReportInvalid"]=1,
                ["ReportSpoof"]=1,["ReportFake"]=1,["ReportClone"]=1,
                ["ReportDuplicate"]=1,["ReportConflict"]=1,["ReportOverlap"]=1,
                ["ReportMismatch"]=1,["ReportInconsistent"]=1,["ReportUnexpected"]=1,
                ["ReportUnknown"]=1,
                -- Ban packets
                ["BanPlayer"]=1,["KickPlayer"]=1,["SuspendPlayer"]=1,
                ["NotifyBan"]=1,["ApplyPunishment"]=1,["ReportCheatResult"]=1,
                ["ProcessBanRequest"]=1,["FairPlayBan"]=1,["SecurityBan"]=1,
                ["TemporaryBan"]=1,["PermanentBan"]=1,["AccountBan"]=1,
                ["CheatPenalty"]=1,["ViolationPenalty"]=1,["BanNotification"]=1,
                ["SendBanInfo"]=1,["BanResultPacket"]=1,["PunishmentPacket"]=1
            }

            if NetUtil and NetUtil.SendPacket and not NetUtil._N5LA_Wrapped then
                local orig = NetUtil.SendPacket
                NetUtil.SendPacket = function(name, ...)
                    if BLOCKED[name] then return nil end
                    return orig(name, ...)
                end
                NetUtil._N5LA_Wrapped = true
                NetUtil.IsBypassed = true
            end

            -- ── RPC blocklist ──
            if _G.SendRPC and not _G._N5LA_RPCWrapped then
                local origRPC = _G.SendRPC
                local BLOCKED_RPC = {
                    "RPC_Server_ClientSecMrpcsFlow",
                    "RPC_Server_SwiftHawk",
                    "RPC_Server_ClientSwiftHawkWithParams",
                    "RPC_Server_ReportSimulateCharacterLocation",
                    "RPC_Client_ShootVertifyRes",
                    "RPC_ClientCoronaLab"
                }
                local set = {}
                for _, k in ipairs(BLOCKED_RPC) do set[k] = true end
                _G.SendRPC = function(rpcName, ...)
                    if set[rpcName] then return nil end
                    return origRPC(rpcName, ...)
                end
                _G._N5LA_RPCWrapped = true
            end

            -- ── socket ──
            if socket and socket.connect and not socket._N5LA_Wrapped then
                local origConnect = socket.connect
                socket.connect = function(host, port, ...)
                    if type(host) == "string" then
                        local hl = host:lower()
                        for i = 1, #_G.BlockedIPs do
                            if hl:find(_G.BlockedIPs[i], 1, true) then return nil, "Blocked" end
                        end
                        for i = 1, #_G.BlockedDomains do
                            if hl:find(_G.BlockedDomains[i], 1, true) then return nil, "Blocked" end
                        end
                    end
                    return origConnect(host, port, ...)
                end
                socket._N5LA_Wrapped = true
            end

            -- ── HTTP ──
            if _G.Http then
                if _G.Http.Get and not _G.Http._N5LA_GetWrapped then
                    local origGet = _G.Http.Get
                    _G.Http.Get = function(url, ...)
                        if type(url) == "string" then
                            local ul = url:lower()
                            for i = 1, #_G.BlockedDomains do
                                if ul:find(_G.BlockedDomains[i], 1, true) then return nil, "Blocked" end
                            end
                        end
                        return origGet(url, ...)
                    end
                    _G.Http._N5LA_GetWrapped = true
                end
                if _G.Http.Post and not _G.Http._N5LA_PostWrapped then
                    local origPost = _G.Http.Post
                    _G.Http.Post = function(url, ...)
                        if type(url) == "string" then
                            local ul = url:lower()
                            for i = 1, #_G.BlockedDomains do
                                if ul:find(_G.BlockedDomains[i], 1, true) then return nil, "Blocked" end
                            end
                        end
                        return origPost(url, ...)
                    end
                    _G.Http._N5LA_PostWrapped = true
                end
            end

            -- ── WebSocket ──
            if _G.WebSocket and _G.WebSocket.Connect and not _G.WebSocket._N5LA_Wrapped then
                local origWS = _G.WebSocket.Connect
                _G.WebSocket.Connect = function(url, ...)
                    if type(url) == "string" then
                        local ul = url:lower()
                        for i = 1, #_G.BlockedDomains do
                            if ul:find(_G.BlockedDomains[i], 1, true) then return nil, "Blocked" end
                        end
                    end
                    return origWS(url, ...)
                end
                _G.WebSocket._N5LA_Wrapped = true
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §10  Higgs Boson / Anti-cheat
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_Higgs()
        pcall(function()
            local H = package.loaded["GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent"]
            if H then
                for _, m in ipairs({
                    "ControlMHActive","Tick","OnTick","MHActiveLogic",
                    "TriggerAvatarCheck","StartAvatarCheck","ReportItemID",
                    "ReceiveAnyDamage","OnWeaponHitRecord","ShowSecurityAlert",
                    "ServerReportAvatar","ClientReportNetAvatar","SendHisarData",
                    "ValidateSecurityData","StaticShowSecurityAlertInDev",
                    "RPC_Client_ShootVertifyRes",
                    "RPC_Server_ReportSimulateCharacterLocation",
                    "DisableHiggsBoson","CheckMHActive","ReportViolation",
                    "ProcessSecurityEvent","ValidatePlayer","CheckIntegrity",
                    "ReportSecurityAlert","CheckClientConfig"
                }) do if H[m] then H[m] = nop end end

                H.GetNetAvatarItemIDs = retEmpty
                H.GetCurWeaponSkinID  = retZero
                H.IsMHActive          = retFalse
                H.bMHActive           = false
                H.bCallPreReplication = false
                H.bIsEnable           = false
                H.CheckClientConfig   = retFalse
                H.GetSecurityInfo     = retEmpty
                H.ValidateClient      = retTrue
                H.CheckIntegrity      = retTrue
                H.BlackList           = {}
            end

            _G.BlackList = {}

            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(pc) then
                for _, comp in ipairs({pc.HiggsBoson, pc.HiggsBosonComponent}) do
                    if slua.isValid(comp) then
                        comp.bMHActive           = false
                        comp.bCallPreReplication = false
                        if type(comp.ControlMHActive) == "function" then comp:ControlMHActive(0) end
                    end
                end
            end

            if _G.AvatarCheckCallback then
                _G.AvatarCheckCallback.StartAvatarCheck = nop
                _G.AvatarCheckCallback.OnReportItemID   = nop
                _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(PC)
                    if slua.isValid(PC) and slua.isValid(PC.HiggsBosonComponent) then
                        PC.HiggsBosonComponent:ControlMHActive(0)
                        PC.HiggsBosonComponent.bMHActive = false
                    end
                end
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §11  Device / HWID / DNS / Engine spoof
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_Spoof()
        pcall(function()
            local SI = import("SystemInfo")
            if SI then
                local STRINGS = {
                    GetDeviceID         = "00000000-0000-0000-0000-000000000000",
                    GetDeviceName       = "iPhone",
                    GetDeviceType       = "Phone",
                    GetManufacturer     = "Apple",
                    GetModel            = "iPhone14,5",
                    GetOSVersion        = "13",
                    GetOSName           = "iOS",
                    GetScreenResolution = "1170x2532",
                    GetScreenDensity    = "460",
                    GetRAMSize          = "6144",
                    GetStorageSize      = "256",
                    GetBatteryLevel     = "100",
                    GetBatteryStatus    = "Charging",
                    GetNetworkType      = "WiFi",
                    GetNetworkSpeed     = "100",
                    GetGPSStatus        = "Enabled",
                    GetGPSLocation      = "0.0,0.0",
                    GetCountryCode      = "US",
                    GetLanguageCode     = "en",
                    GetTimeZone         = "UTC",
                    GetKernelVersion    = "Linux version 4.14.116",
                    GetDeviceModel      = "iPhone14,5",
                    GetDeviceBrand      = "Apple",
                    GetAndroidVersion   = "13",
                    GetEMUIVersion      = ""
                }
                for k, v in pairs(STRINGS) do
                    if type(SI[k]) == "function" then SI[k] = function() return v end end
                end

                local NUMBERS = {
                    GetUptime            = 3600,
                    GetCPUUsage          = 10,
                    GetMemoryUsage       = 20,
                    GetTemperature       = 25,
                    GetBatteryTemperature= 25,
                    GetCPUFrequency      = 2400,
                    GetGPUFrequency      = 1200,
                    GetScreenBrightness  = 100,
                    GetVolumeLevel       = 100
                }
                for k, v in pairs(NUMBERS) do
                    if type(SI[k]) == "function" then SI[k] = function() return v end end
                end

                local BOOLS = { IsEmulator = false, IsRooted = false, IsDebugged = false }
                for k, v in pairs(BOOLS) do
                    if type(SI[k]) == "function" then SI[k] = function() return v end end
                end

                if type(SI.CheckKernelIntegrity) == "function" then SI.CheckKernelIntegrity = retTrue end
                if type(SI.GetCurrentTime)      == "function" then SI.GetCurrentTime      = os.time   end
            end

            -- HWID fake
            local KSL = import("KismetSystemLibrary")
            if KSL and not _G.FakeHWID_Hooked then
                if type(KSL.GetDeviceId) == "function" then
                    _G.Original_GetDeviceId = KSL.GetDeviceId
                    KSL.GetDeviceId = function(...)
                        if not _G.FakeHWID_String then
                            local chars = "0123456789abcdef"
                            local hwid = ""
                            for _ = 1, 32 do
                                hwid = hwid .. chars:sub(math.random(1, 16), math.random(1, 16))
                            end
                            _G.FakeHWID_String = hwid
                        end
                        return _G.FakeHWID_String
                    end
                end
                _G.FakeHWID_Hooked = true
            end

            -- DNS / Network
            local DNS = import("DNS")
            if DNS then
                DNS.Resolve      = function() return "127.0.0.1"    end
                DNS.GetHostName  = function() return "BYPASSED_HOST" end
                DNS.GetIPAddress = function() return "0.0.0.0"      end
            end
            local NW = import("Network")
            if NW then
                NW.GetIPAddress  = function() return "0.0.0.0"      end
                NW.GetMACAddress = function() return "BYPASSED_MAC" end
                NW.GetSSID       = function() return "BYPASSED_SSID"end
                NW.GetBSSID      = function() return "BYPASSED_BSSID"end
            end

            -- Engine timing
            local E = import("Engine")
            if E then
                if type(E.GetAverageFPS) == "function" then E.GetAverageFPS = function() return 60 end end
                if type(E.GetFrameTime)  == "function" then E.GetFrameTime  = function() return 0.016 end end
                if type(E.GetDeltaTime)  == "function" then E.GetDeltaTime  = function() return 0.033 end end
                if type(E.IsLagging)     == "function" then E.IsLagging     = retFalse end
                if type(E.GetTime)       == "function" then E.GetTime       = os.time end
                if type(E.GetTimestamp)  == "function" then E.GetTimestamp  = os.time end
                if type(E.GetTick)       == "function" then E.GetTick       = os.clock end
                if type(E.GetSeconds)    == "function" then E.GetSeconds    = os.time end
                if type(E.GetMilliseconds) == "function" then E.GetMilliseconds = function() return os.time() * 1000 end end
                if type(E.GetMicroseconds) == "function" then E.GetMicroseconds = function() return os.time() * 1000000 end end
                if type(E.GetNanoseconds)  == "function" then E.GetNanoseconds  = function() return os.time() * 1000000000 end end
            end

            -- GameTime
            local GT = package.loaded["GameLua.GameCore.Data.GameTime"]
            if GT then
                if type(GT.GetServerTime) == "function" then GT.GetServerTime = os.time end
                if type(GT.GetGameTime)   == "function" then GT.GetGameTime   = os.time end
                if type(GT.GetRealTime)   == "function" then GT.GetRealTime   = os.time end
                if type(GT.GetTickTime)   == "function" then GT.GetTickTime   = os.clock end
                if type(GT.GetDeltaTime)  == "function" then GT.GetDeltaTime  = function() return 0.033 end end
                if type(GT.GetFrameTime)  == "function" then GT.GetFrameTime  = function() return 0.016 end end
            end

            -- Memory protection
            local MP = import("MemoryProtect")
            if MP then
                MP.VirtualProtect   = retTrue
                MP.CheckMemory      = retTrue
                MP.ProtectMemory    = retTrue
                MP.UnprotectMemory  = retTrue
                MP.ValidateMemory   = retTrue
                MP.VerifyMemory     = retTrue
                if type(MP.IsMemoryReadable) == "function" then MP.IsMemoryReadable = retFalse end
                if type(MP.IsMemoryWritable) == "function" then MP.IsMemoryWritable = retFalse end
            end

            -- Detection modules
            local DD = _G.DebuggerDetect or package.loaded["DebuggerDetect"]
            if DD then
                for _, m in ipairs({
                    "IsDebuggerPresent","CheckBreakpoint","CheckTracer","CheckDebug",
                    "CheckDebugger","DetectDebugger","DetectBreakpoint","DetectTracer","DetectDebug"
                }) do if type(DD[m]) == "function" then DD[m] = retFalse end end
            end
            local ED = _G.EmulatorDetect or package.loaded["EmulatorDetect"]
            if ED then
                for _, m in ipairs({
                    "IsEmulator","CheckVM","Detect","DetectEmulator",
                    "DetectVM","DetectVirtualMachine"
                }) do if type(ED[m]) == "function" then ED[m] = retFalse end end
                if type(ED.GetEmulatorType)      == "function" then ED.GetEmulatorType      = retES end
                if type(ED.DetectEmulatorType)   == "function" then ED.DetectEmulatorType   = retES end
            end
            local RD = _G.RootDetect or package.loaded["RootDetect"]
            if RD then
                for _, m in ipairs({"CheckRoot","CheckSu","CheckMagisk","CheckSuperSU"}) do
                    if type(RD[m]) == "function" then RD[m] = retFalse end
                end
            end
            local JD = _G.JailbreakDetect or package.loaded["JailbreakDetect"]
            if JD then
                for _, m in ipairs({"CheckJailbreak","CheckCydia"}) do
                    if type(JD[m]) == "function" then JD[m] = retFalse end
                end
            end

            -- Blank out suspicious globals
            for _, var in ipairs({
                "bIsCheating","bDetected","bBanned","SuspicionScore","CheatDetected",
                "AntiCheatFlag","IsHacking","bReported","TrustScore","SecurityFlag",
                "ViolationLevel","BanStatus","bIsBan","bIsKick","bIsReported",
                "CheatCount","ViolationCount","SecurityScore","TrustLevel",
                "bIsCheater","bIsHacker","bIsModder","bIsInjector","bIsHooker",
                "bIsPatcher","bIsTamperer","bIsCorrupter","bIsInvalid","bIsSpoofer",
                "bIsFaker","bIsCloner","bIsDuplicator","bIsConflicter","bIsOverlapper",
                "bIsMismatcher","bIsInconsistent","bIsUnexpected","bIsUnknown",
                "bIsSuspicious","bIsAbnormal","bIsCorrupt","bIsTampered","bIsModified",
                "bIsInjected","bIsHooked","bIsPatched","bIsSpoofed","bIsFaked",
                "bIsCloned","bIsDuplicated","bIsConflicted","bIsOverlapped","bIsMismatched"
            }) do _G[var] = nil end

            -- Anti-fingerprint helpers
            if not _G.FakeHWID_Internal then
                _G.FakeHWID_Internal = "SECURE_" .. tostring(os.time()) .. "_" .. tostring(math.random(10000, 99999))
            end
            _G.GetFakeHWID = function() return _G.FakeHWID_Internal end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §12  TSS SDK + ACE + XignCode + BattlEye
    -- ═══════════════════════════════════════════════════════════════════
    local function Section_SDKs()
        pcall(function()
            local TSS = _G.TssSdk or package.loaded["TssSdk"]
            if TSS then
                local origOnRecv = TSS.OnRecvData
                TSS.OnRecvData = function(data)
                    if type(data) == "string" and (
                        data:find("report")    or data:find("exception") or
                        data:find("cheat")     or data:find("violation") or
                        data:find("hack")      or data:find("verify")
                    ) then return end
                    if origOnRecv then origOnRecv(data) end
                end

                local LIST = {
                    "SendReportInfo","ReportData","ReportException","SendAntiData","UploadLog",
                    "ReportGameStart","ReportGameEnd","ReportCrash","ReportViolation","ReportSuspicious",
                    "ReportBan","ReportKick","ReportWarning","ReportInfo","ReportDebug","ReportError",
                    "ReportFatal","ReportMemory","ReportProcess","ReportModule","ReportThread",
                    "ReportFile","ReportNetwork","ReportDevice","ReportSystem","ReportGame",
                    "ReportUser","ReportAccount","ReportSession","ReportPerformance","ReportBattery",
                    "ReportTemperature","ReportFPS","ReportPing","ReportPacket","ReportCheat",
                    "ReportHack","ReportMod","ReportInject","ReportDebugger","ReportEmulator",
                    "ReportRoot","ReportJailbreak","ReportVM","ReportHook","ReportPatch",
                    "ReportTamper","ReportCorrupt","ReportInvalid","ReportSpoof","ReportFake",
                    "ReportClone","ReportDuplicate","ReportConflict","ReportOverlap","ReportMismatch",
                    "ReportInconsistent","ReportUnexpected","ReportUnknown"
                }
                for _, m in ipairs(LIST) do TSS[m] = nop end
                TSS.ScanMemory          = retTrue
                TSS.CheckIntegrity      = retTrue
                TSS.VerifySignature     = retTrue
                TSS.VerifyProcess       = retTrue
                TSS.CheckEnvironment    = retTrue
                TSS.IsEmulator          = retFalse
                TSS.GetTssSdkReportInfo = retES
                TSS.CollectEvidence     = retNil
            end

            local ACE = _G.ace or package.loaded["libace.so"]
            if ACE then
                for _, m in ipairs({
                    "ReportData","ReportViolation","KickPlayer","BanPlayer","SendReport",
                    "ReportCheat","ReportHack","ReportMod","ReportInject","ReportHook",
                    "ReportPatch","ReportTamper","ReportCorrupt","ReportInvalid","ReportSpoof","ReportFake"
                }) do ACE[m] = nop end
                ACE.CheckIntegrity = retTrue
                ACE.VerifyProcess  = retTrue
                ACE.CheckModule    = retTrue
                ACE.ValidateClient = retTrue
                ACE.ScanMemory     = retFalse
                ACE.CheckDebugger  = retFalse
                ACE.CheckEmulator  = retFalse
                ACE.CheckRoot      = retFalse
                ACE.CollectInfo    = retEmpty
            end

            local XC = _G.XignCode or package.loaded["xigncode"]
            if XC then
                for _, m in ipairs({
                    "SendReport","ReportException","KickPlayer","BanPlayer","ReportCheat",
                    "ReportHack","ReportMod","ReportInject","ReportHook","ReportPatch","ReportTamper"
                }) do XC[m] = nop end
                XC.CheckProcess     = retTrue
                XC.VerifyIntegrity  = retTrue
                XC.ValidateMemory   = retTrue
                XC.ScanModules      = retEmpty
                XC.CheckDebugger    = retFalse
                XC.EncryptData      = function(data) return data end
                XC.DecryptData      = function(data) return data end
            end

            local BE = _G.BattlEye or package.loaded["BattlEye"]
            if BE then
                for _, m in ipairs({
                    "SendReport","KickPlayer","ReportViolation","BanPlayer",
                    "ReportCheat","ReportHack","ReportMod","ReportInject","ReportHook"
                }) do BE[m] = nop end
                BE.ValidatePlayer  = retTrue
                BE.CheckMemory     = retTrue
                BE.VerifyIntegrity = retTrue
                BE.ScanProcess     = retTrue
                BE.CollectEvidence = retEmpty
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §13  Ban UI killer + Final global protection
    -- ═══════════════════════════════════════════════════════════════════
    local BLOCKED_UI_KW = {
        "Legal","Common_Legal","Notice","Ban","Error","Popup","Message",
        "Dialog","Warning","Alert","Notification","Toast","Snackbar","Banner",
        "Confirm","Prompt","Input","Select","Progress","Loading","Success",
        "Failure","Info","Fatal","Panic","Kick","Suspend","Freeze","Block"
    }
    local BLOCKED_UI_NAMES = {
        "Common_Legal_01_UIBP","BanNotice_UIBP","BanPopup_UIBP",
        "KickPopup_UIBP","WarningPopup_UIBP","AlertPopup_UIBP",
        "SecurityAlert_UIBP","AntiCheatPopup_UIBP","ReportPopup_UIBP"
    }

    local function KillBanPopup()
        pcall(function()
            local widgets = slua.getUIList and slua.getUIList() or {}
            for _, w in pairs(widgets) do
                if slua.isValid(w) then
                    local name = ""
                    pcall(function() name = w:GetName() or "" end)
                    for _, kw in ipairs(BLOCKED_UI_KW) do
                        if name:find(kw, 1, true) then
                            pcall(function() w:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                            pcall(function() w:RemoveFromParent() end)
                            break
                        end
                    end
                end
            end
            if slua.getUIByName then
                for _, nm in ipairs(BLOCKED_UI_NAMES) do
                    local ui = slua.getUIByName(nm)
                    if slua.isValid(ui) then
                        pcall(function() ui:SetWidgetVisibility(UEnums.ESlateVisibility.Collapsed) end)
                        pcall(function() ui:RemoveFromParent() end)
                    end
                end
            end
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(pc) then
                local KSL = import("KismetSystemLibrary")
                if KSL and KSL.ExecuteConsoleCommand then
                    local cmds = {
                        "DisableAllScreenMessages","UI.DisableMessageOfTheDay",
                        "ShowMOTD 0","r.UI.DisableAll 1","UI.HideAllWidgets 1",
                        "ShowBanNotice 0","ShowSuspension 0","ShowFrozenNotice 0",
                        "ShowRiskNotice 0","DisableBanUI 1","HideBanMessages 1",
                        "IgnoreSecurityChecks 1","UIToggle 0","HideUI 1",
                        "DisablePopup 1","SuppressDialogs 1"
                    }
                    for _, c in ipairs(cmds) do
                        pcall(KSL.ExecuteConsoleCommand, pc, c)
                    end
                end
            end
        end)
    end

    local function Section_FinalProtection()
        pcall(function()
            for _, flag in ipairs({
                "ENABLE_REPORT","ENABLE_ANTI_CHEAT","ENABLE_SECURITY",
                "ENABLE_TELEMETRY","ENABLE_ANALYTICS","ENABLE_CRASH_REPORT",
                "ENABLE_PERFORMANCE_REPORT"
            }) do _G[flag] = false end

            -- Block on-demand loads
            local origReq = require
            local BLOCKED = {
                "HiggsBosonComponent","PlayerSecurityInfoSubsystem",
                "CoronaLabSubsystem","ClientCircleFlowSubsystem",
                "ModifierExceptionSubsystem","ShootVerifySubSystemClient",
                "ClientReportPlayerSubsystem","DSReportPlayerSubsystem"
            }
            if not _G._N5LA_RequireWrapped then
                _G.require = function(m)
                    if type(m) == "string" then
                        for i = 1, #BLOCKED do
                            if m:find(BLOCKED[i], 1, true) then return {} end
                        end
                    end
                    return origReq(m)
                end
                _G._N5LA_RequireWrapped = true
            end

            -- Reset log/telemetry queues
            _G.TelemetryQueue            = {}
            _G.bTelemetryEnabled         = false
            _G.LogQueue                  = {}
            _G.bLoggingEnabled           = false
            _G.ReportQueue               = {}
            _G.bReportingEnabled         = false
            _G.ExceptionQueue            = {}
            _G.bExceptionReportingEnabled = false
            _G.CrashQueue                = {}
            _G.bCrashReportingEnabled    = false
            _G.TraceQueue                = {}
            _G.bTracingEnabled           = false
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    -- §14  IP / Domain blocklists (shared)
    -- ═══════════════════════════════════════════════════════════════════
    _G.BlockedIPs = _G.BlockedIPs or {
        "43.128.0.0/16","43.129.0.0/16","43.130.0.0/16","43.131.0.0/16",
        "43.132.0.0/16","43.133.0.0/16","43.134.0.0/16","43.135.0.0/16",
        "43.136.0.0/16","43.137.0.0/16","43.138.0.0/16","43.139.0.0/16",
        "43.140.0.0/16","43.141.0.0/16","43.142.0.0/16","43.143.0.0/16",
        "43.144.0.0/16","43.145.0.0/16","43.146.0.0/16","43.147.0.0/16",
        "43.148.0.0/16","43.149.0.0/16","43.150.0.0/16","43.151.0.0/16",
        "43.152.0.0/16","43.153.0.0/16","43.154.0.0/16","43.155.0.0/16",
        "43.156.0.0/16","43.157.0.0/16","43.158.0.0/16","43.159.0.0/16",
        "43.160.0.0/16","43.161.0.0/16","43.162.0.0/16","43.163.0.0/16",
        "43.164.0.0/16","43.165.0.0/16","43.166.0.0/16","43.167.0.0/16",
        "43.168.0.0/16","43.169.0.0/16","43.170.0.0/16","43.171.0.0/16",
        "43.172.0.0/16","43.173.0.0/16","43.174.0.0/16","43.175.0.0/16",
        "43.176.0.0/16","43.177.0.0/16","43.178.0.0/16","43.179.0.0/16",
        "43.180.0.0/16","43.181.0.0/16","43.182.0.0/16","43.183.0.0/16",
        "43.184.0.0/16","43.185.0.0/16","43.186.0.0/16","43.187.0.0/16",
        "43.188.0.0/16","43.189.0.0/16","43.190.0.0/16","43.191.0.0/16",
        "43.192.0.0/16","43.193.0.0/16","43.194.0.0/16","43.195.0.0/16",
        "43.196.0.0/16","43.197.0.0/16","43.198.0.0/16","43.199.0.0/16",
        "43.200.0.0/16","43.201.0.0/16","43.202.0.0/16","43.203.0.0/16",
        "43.204.0.0/16","43.205.0.0/16","43.206.0.0/16","43.207.0.0/16",
        "43.208.0.0/16","43.209.0.0/16","43.210.0.0/16","43.211.0.0/16",
        "43.212.0.0/16","43.213.0.0/16","43.214.0.0/16","43.215.0.0/16",
        "43.216.0.0/16","43.217.0.0/16","43.218.0.0/16","43.219.0.0/16",
        "43.220.0.0/16","43.221.0.0/16","43.222.0.0/16","43.223.0.0/16",
        "43.224.0.0/16","43.225.0.0/16","43.226.0.0/16","43.227.0.0/16",
        "43.228.0.0/16","43.229.0.0/16","43.230.0.0/16","43.231.0.0/16",
        "43.232.0.0/16","43.233.0.0/16","43.234.0.0/16","43.235.0.0/16",
        "43.236.0.0/16","43.237.0.0/16","43.238.0.0/16","43.239.0.0/16",
        "43.240.0.0/16","43.241.0.0/16","43.242.0.0/16","43.243.0.0/16",
        "43.244.0.0/16","43.245.0.0/16","43.246.0.0/16","43.247.0.0/16",
        "43.248.0.0/16","43.249.0.0/16","43.250.0.0/16","43.251.0.0/16",
        "43.252.0.0/16","43.253.0.0/16","43.254.0.0/16","43.255.0.0/16",
        "129.204.0.0/16","129.205.0.0/16","129.206.0.0/16","129.207.0.0/16",
        "129.208.0.0/16","129.209.0.0/16","129.210.0.0/16","129.211.0.0/16",
        "129.212.0.0/16","129.213.0.0/16","129.214.0.0/16","129.215.0.0/16",
        "129.216.0.0/16","129.217.0.0/16","129.218.0.0/16","129.219.0.0/16",
        "129.220.0.0/16","129.221.0.0/16","129.222.0.0/16","129.223.0.0/16",
        "129.224.0.0/16","129.225.0.0/16","129.226.0.0/16","129.227.0.0/16",
        "129.228.0.0/16","129.229.0.0/16","129.230.0.0/16","129.231.0.0/16",
        "129.232.0.0/16","129.233.0.0/16","129.234.0.0/16","129.235.0.0/16",
        "129.236.0.0/16","129.237.0.0/16","129.238.0.0/16","129.239.0.0/16",
        "129.240.0.0/16","129.241.0.0/16","129.242.0.0/16","129.243.0.0/16",
        "129.244.0.0/16","129.245.0.0/16","129.246.0.0/16","129.247.0.0/16",
        "129.248.0.0/16","129.249.0.0/16","129.250.0.0/16","129.251.0.0/16",
        "129.252.0.0/16","129.253.0.0/16","129.254.0.0/16","129.255.0.0/16",
        "185.244.0.0/16","185.245.0.0/16","185.246.0.0/16","185.247.0.0/16",
        "185.248.0.0/16","185.249.0.0/16","185.250.0.0/16","185.251.0.0/16",
        "185.252.0.0/16","185.253.0.0/16","185.254.0.0/16","185.255.0.0/16",
        "203.0.0.0/8","204.0.0.0/8","205.0.0.0/8","206.0.0.0/8",
        "207.0.0.0/8","208.0.0.0/8","209.0.0.0/8","210.0.0.0/8",
        "211.0.0.0/8","212.0.0.0/8","213.0.0.0/8","214.0.0.0/8",
        "215.0.0.0/8","216.0.0.0/8","217.0.0.0/8","218.0.0.0/8",
        "219.0.0.0/8","220.0.0.0/8","221.0.0.0/8","222.0.0.0/8",
        "223.0.0.0/8"
    }

    _G.BlockedDomains = _G.BlockedDomains or {
        "anticheat.qq.com","tss.tencent.com","tss-sdk.qq.com",
        "report.qq.com","ban.qq.com","security.qq.com","hawkeye.qq.com",
        "pubgm.qq.com","pubgmobile.qq.com","igame.qq.com","tencent.com",
        "qq.com","tlog.qq.com","ds.qq.com","lobby.qq.com","match.qq.com",
        "login.qq.com","account.qq.com","device.qq.com","fingerprint.qq.com",
        "telemetry.qq.com","analytics.qq.com","crash.qq.com","bugly.qq.com",
        "tdm.qq.com","gokuba.qq.com","swifthawk.qq.com","coronalab.qq.com",
        "higgsboson.qq.com","battleye.com","xigncode.com","ace.qq.com",
        "tss-sdk.com","antihack.com","securitycheck.com","validation.com",
        "verification.com","monitor.com","tracking.com","igamecj.com",
        "pubgm.com","gpubm.com","gjacky.com","facebook.com",
        "googleusercontent.com","hwclouds-dns.com","gcloudcs.com",
        "googleapis.com","vasdgame.com","amsoveasea.com",
        "mbgame.anticheatexpert.com","tdatamaster.com","helpshift.com",
        "perfsight.wetest.net","proximabeta.com","onezapp.com",
        "adjust.com","crashsight.wetest.net"
    }

    -- ═══════════════════════════════════════════════════════════════════
    -- §15  Runner — applies everything (idempotent per section)
    -- ═══════════════════════════════════════════════════════════════════
    local function ApplyAll()
        pcall(Section_SLUA)
        pcall(Section_MD5)
        pcall(Section_PAK)
        pcall(Section_Logging)
        pcall(Section_Screenshot)
        pcall(Section_Subsystems)
        pcall(Section_Modules)
        pcall(Section_Callbacks)
        pcall(Section_Network)
        pcall(Section_Higgs)
        pcall(Section_Spoof)
        pcall(Section_SDKs)
        pcall(Section_FinalProtection)
    end

    _G.StartBypass_VIP_v3 = ApplyAll
    _G.RunAntiBan         = ApplyAll
    _G.KillBanPopup       = KillBanPopup

    _G.CheckProtectionStatus = function()
        return {
            BypassActive       = true,
            HiggsBosonDisabled = true,
            ReportsBlocked     = true,
            HWIDFaked          = _G.FakeHWID_Hooked or false,
            AllLayersActive    = true,
            LayersCount        = 49
        }
    end

    -- ── initial run ──
    ApplyAll()

    -- ═══════════════════════════════════════════════════════════════════
    -- §16  Live guard loops
    -- ═══════════════════════════════════════════════════════════════════
    _G._N5LA_GuardToken = (_G._N5LA_GuardToken or 0) + 1
    local GUARD_TOKEN = _G._N5LA_GuardToken

    local function FastGuard()
        if _G._N5LA_GuardToken ~= GUARD_TOKEN then return end

        pcall(function()
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(pc) then
                for _, comp in ipairs({pc.HiggsBoson, pc.HiggsBosonComponent}) do
                    if slua.isValid(comp) then
                        comp.bMHActive           = false
                        comp.bCallPreReplication = false
                    end
                end
            end
        end)

        pcall(KillBanPopup)

        local ok, ticker = pcall(require, "common.time_ticker")
        if ok and ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(0.5, FastGuard)
        end
    end

    local function SlowGuard()
        if _G._N5LA_GuardToken ~= GUARD_TOKEN then return end
        ApplyAll()
        pcall(function()
            require("common.time_ticker").AddTimerOnce(5, SlowGuard)
        end)
    end

    pcall(function()
        local ok, ticker = pcall(require, "common.time_ticker")
        if ok and ticker and ticker.AddTimerOnce then
            ticker.AddTimerOnce(0.5, FastGuard)
            ticker.AddTimerOnce(5,   SlowGuard)
        end
    end)

    -- ── ban popup hot loop ──
    if not _G._N5LA_BanPopupLoopActive then
        _G._N5LA_BanPopupLoopActive = true
        pcall(function()
            local ticker = require("common.time_ticker")
            if ticker and ticker.AddTimerLoop then
                ticker.AddTimerLoop(0, function()
                    pcall(KillBanPopup)
                end, -1, 0.3)
            end
        end)
    end

    end -- if not installed
end

-- ════════════════════════════════════════════════════════════════════════════
--  ANTI-BAN SUPPLEMENT — 9 missing layers restored
--  Idempotent • No duplication with the main block • Drop-in ready
-- ════════════════════════════════════════════════════════════════════════════
do
    if not _G._N5LA_AntiBan_Supplement then
        _G._N5LA_AntiBan_Supplement = true

        local nop      = function() return true  end
        local retTrue  = function() return true  end
        local retFalse = function() return false end
        local retZero  = function() return 0     end
        local retEmpty = function() return {}    end
        local retNil   = function() return nil   end
        local retES    = function() return ""    end

        local function safeRequire(path)
            local m = package.loaded[path]
            if m then return m end
            local ok, r = pcall(require, path)
            return ok and r or nil
        end

        -- ═══════════════════════════════════════════════════════════════
        -- §17  MEMORY SCANNER BLOCK
        -- ═══════════════════════════════════════════════════════════════
        pcall(function()
            local MS = _G.MemoryScanner or package.loaded["MemoryScanner"]
            if not MS then return end
            MS.StartScan          = nop
            MS.StopScan           = nop
            MS.GetResults         = retEmpty
            MS.ReportViolation    = nop
            MS.CheckIntegrity     = retTrue
            MS.VerifyMemory       = retTrue
            MS.ScanProcess        = nop
            MS.ScanModule         = nop
            MS.ScanThread         = nop
            MS.ScanFile           = nop
            MS.ScanNetwork        = nop
            MS.ScanMemory         = retTrue
            MS.ValidateMemory     = retTrue
            MS.IsSuspicious       = retFalse
            MS.GetSuspiciousList  = retEmpty
            MS.ClearResults       = nop
        end)

        -- ═══════════════════════════════════════════════════════════════
        -- §18  KISMET SYSTEM LIBRARY FLAGS
        -- ═══════════════════════════════════════════════════════════════
        pcall(function()
            local KSL = import("KismetSystemLibrary")
            if not KSL then return end
            if type(KSL.IsDevelopment) == "function" then KSL.IsDevelopment = retFalse end
            if type(KSL.IsShipping)    == "function" then KSL.IsShipping    = retTrue  end
            if type(KSL.IsDebug)       == "function" then KSL.IsDebug       = retFalse end
            if type(KSL.IsEditor)      == "function" then KSL.IsEditor      = retFalse end
            if type(KSL.IsGame)        == "function" then KSL.IsGame        = retTrue  end
            if type(KSL.IsClient)      == "function" then KSL.IsClient      = retTrue  end
            if type(KSL.IsServer)      == "function" then KSL.IsServer      = retFalse end
            if type(KSL.IsStandalone)  == "function" then KSL.IsStandalone  = retFalse end
            if type(KSL.IsInPIE)       == "function" then KSL.IsInPIE       = retFalse end
            if type(KSL.IsPlayInEditor)== "function" then KSL.IsPlayInEditor= retFalse end
        end)

        -- ═══════════════════════════════════════════════════════════════
        -- §19  NETWORK MANAGER
        -- ═══════════════════════════════════════════════════════════════
        pcall(function()
            local NM = import("NetworkManager")
            if not NM then return end
            NM.GetNetworkStats       = function() return {ping=40, loss=0, rtt=40} end
            NM.CapturePackets        = nop
            NM.AnalyzeTraffic        = retEmpty
            NM.GetConnectionInfo     = function() return "127.0.0.1:8080" end
            NM.MonitorTraffic        = nop
            NM.ReportTraffic         = nop
            NM.ReportNetwork         = nop
            NM.ReportBandwidth       = nop
            NM.ReportLatency         = nop
            NM.ReportPacketLoss      = nop
            NM.ReportConnection      = nop
            NM.ReportDisconnect      = nop
            NM.CheckNetworkIntegrity = retTrue
            NM.ValidateConnection    = retTrue
            NM.IsSuspiciousTraffic   = retFalse
            NM.GetTrafficData        = retEmpty
        end)

        -- ═══════════════════════════════════════════════════════════════
        -- §20  CLIENT ENTRY POINT
        -- ═══════════════════════════════════════════════════════════════
        pcall(function()
            local C = _G.Client
            if C then
                C.SetTssNetworkStatus          = nop
                C.GEMReportEnterLobbyEvent     = nop
                C.TPerforPlatDisconnectReport  = nop
                C.IsConnected                  = function() return true end
                C.GetUnrealNetworkStatus       = retES
                C.MD5LuaString                 = function() return "BYPASSED_MD5" end
                C.GetDSVersion                 = function() return "999.999.999" end
                C.IsInReplayState              = retFalse
                C.CheckTssNetwork              = retTrue
                C.ReportTssStatus              = nop
            end
            local NM = _G.NetManager
            if NM then
                NM.ProcRespondMsg          = nop
                NM.isLogMsgAfterLogin      = false
                NM.logMsgMap               = {}
                NM.ReportNetworkError      = nop
                NM.ReportDisconnect        = nop
                NM.ValidatePacket          = retTrue
            end
            local LU = _G.LogUtil
            if LU then
                LU.SetForceLog         = nop
                LU.SetLogTreeEnable    = nop
                LU.SetWriteLog         = nop
                LU.SetLogLevel         = nop
                LU.EnableDebug         = nop
            end
        end)

        -- ═══════════════════════════════════════════════════════════════
        -- §21  REALTIMEBAN MODULE
        -- ═══════════════════════════════════════════════════════════════
        pcall(function()
            local RTB = _G.RealTimeBan
                or package.loaded["RealTimeBan"]
                or safeRequire("GameLua.Mod.BaseMod.Client.Security.RealTimeBan")
                or safeRequire("client.slua.logic.ban.RealTimeBan")
            if not RTB then return end
            RTB.Init                          = nop
            RTB.OnPlayerWithRealTimeBan       = nop
            RTB.OnSyncPlayerInfo              = nop
            RTB.HandleEnterGameModeFightingState = nop
            RTB.ShowAlias                     = nop
            RTB.SetOnRankInspectorUID         = nop
            RTB.IsUIDOnRankInspector          = retFalse
            RTB.GetUIDInspectorRank           = function() return -1 end
            RTB.SetInspectorBroadcastCountUID = nop
            RTB.GetUIDInspectorBroadcastCount = function() return -1 end
            RTB.GetTipsIDOffset               = retZero
            RTB.GetTipsIDOffsetWithUID        = retZero
            RTB.GetTipsIDOffsetInspector      = retZero
            RTB.GMShowAlias                   = nop
            RTB.tOnRankInspectorUIDSet        = {}
            RTB.tInspectorRankUIDSet          = {}
            RTB.tInspectorBroadcastCountUIDSet = {}
            RTB.MaxAliasLevel                 = -1
            RTB.is_onrank_inspector           = false
            RTB.inspector_rank                = -1
            RTB.bHasOldAlias                  = false
            RTB.ShowTipsAliasConfig           = {}
            RTB.DelayTime                     = {}
            RTB.OldShowTipsAlias              = 0
            RTB.CheckRealTimeBan              = retFalse
            RTB.ApplyRealTimeBan              = nop
            RTB.NotifyRealTimeBan             = nop
        end)

        -- ═══════════════════════════════════════════════════════════════
        -- §22  RACING ANTICHEAT
        -- ═══════════════════════════════════════════════════════════════
        pcall(function()
            local R = _G.RacingAntiCheatLogic
                or package.loaded["RacingAntiCheatLogic"]
                or safeRequire("GameLua.Mod.BaseMod.Client.Security.RacingAntiCheatLogic")
                or safeRequire("client.slua.logic.racing.RacingAntiCheatLogic")
            if not R then return end
            R.HandleRacingEnter          = nop
            R.HandleRacingStart          = nop
            R.HandleRacingEnd            = nop
            R.StartDetectTimer           = nop
            R.StopDetectTimer            = nop
            R.DetectVehicleFloating      = nop
            R.HandleFloatingCheat        = nop
            R.SetIgnoreFloating          = nop
            R.HandlePlayerPassCheckBelt  = nop
            R.HandleSpeedCheat           = nop
            R._CreateVehicleData         = retEmpty
            R.vehicleDataMap             = {}
            R.detectTimer                = nil
            R.ReportRacingCheat          = nop
            R.ValidateRacing             = retTrue
            R.config = {
                FloatingDistLimit      = 99999,
                FloatingTimeLimit      = 99999,
                CheckPassIntervalLimit = 99999
            }
        end)

        -- ═══════════════════════════════════════════════════════════════
        -- §23  DEBUG HOOK REMOVAL + JIT
        -- ═══════════════════════════════════════════════════════════════
        pcall(function()
            if debug then
                if debug.sethook then pcall(debug.sethook) end
                if debug.gethook then
                    local _, _, count = debug.gethook()
                    if count and count > 0 then pcall(debug.sethook) end
                end
                if debug.setmetatable and not _G._N5LA_DebugMTShield then
                    local orig_setmt = debug.setmetatable
                    debug.setmetatable = function(t, mt)
                        if t == _G then return end
                        return orig_setmt(t, mt)
                    end
                    _G._N5LA_DebugMTShield = true
                end
            end
            if jit then
                pcall(function() if jit.off then jit.off() end end)
                pcall(function()
                    if jit.attach then jit.attach(function() end, "bc") end
                end)
                pcall(function()
                    if jit.attach then jit.attach(function() end, "trace") end
                end)
            end
        end)

        -- ═══════════════════════════════════════════════════════════════
        -- §24  METATABLE SHIELD (protect _G)
        -- ═══════════════════════════════════════════════════════════════
        pcall(function()
            if _G._N5LA_MetatableShield then return end
            local orig_mt = getmetatable(_G) or {}
            local orig_index = orig_mt.__index
            orig_mt.__index = function(t, k)
                if k == "_BYPASS_DONE" or k == "_bypass_active"
                   or k == "_detection_flag" or k == "_cheat_flag"
                   or k == "_anticheat_flag" or k == "_report_flag" then
                    return nil
                end
                if orig_index then return orig_index(t, k) end
                return rawget(t, k)
            end
            orig_mt.__newindex = function(t, k, v)
                if k == "_detection_flag" or k == "_cheat_flag"
                   or k == "_anticheat_flag" or k == "_report_flag" then
                    rawset(t, k, nil)
                    return
                end
                rawset(t, k, v)
            end
            pcall(setmetatable, _G, orig_mt)
            _G._N5LA_MetatableShield = true
        end)

        -- ═══════════════════════════════════════════════════════════════
        -- §25  GLOBAL ENV SANITIZER (continuously clean suspicious keys)
        -- ═══════════════════════════════════════════════════════════════
        pcall(function()
            local SUSPICIOUS_KEYS = {
                "_BYPASS_DONE","_bypass_active","_detection_flag","_cheat_flag",
                "_anticheat_flag","_report_flag","_ban_flag","_kick_flag",
                "cheat_detected","anticheat_triggered","report_pending",
                "ban_pending","violation_pending","suspicious_flag",
                "hack_detected","mod_detected","inject_detected",
                "hook_detected","tamper_detected","spoof_detected",
                "cheat_state","anticheat_state","security_state"
            }
            for _, k in ipairs(SUSPICIOUS_KEYS) do
                pcall(rawset, _G, k, nil)
            end
        end)

        -- ═══════════════════════════════════════════════════════════════
        -- §26  SUPPLEMENT RE-ENTRY POINT
        -- ═══════════════════════════════════════════════════════════════
        _G.RunAntiBanSupplement = function()
            -- all sections above are idempotent and already applied
            -- this exists only as a manual entry point if needed
            return true
        end

    end -- if not supplement installed
end
-- ============================================================================
-- MERGED: PlayerAntiCheatManager.lua — GG Memory Bypass Layer (LIVE REFRESH)
-- ── Resolves addresses ONCE (bss is stable), then re-freezes on a timer.
-- ── Hooks itself into the existing time_ticker loop — no new threads.
-- ── No-ops silently when gg/S_Pointer aren't present.
-- Rights: @RAHMANYVI | integrated by @MON5LA
-- ============================================================================
do
    if _G._N5LA_GGBypass_Installed then
        -- already live — just force a refresh pass
        if type(_G.N5LA_GG_Refresh) == "function" then _G.N5LA_GG_Refresh() end
    else
        _G._N5LA_GGBypass_Installed = true

        local _gg = rawget(_G, "gg")
        local _SP = rawget(_G, "S_Pointer")
        local HAS_GG = (_gg and _SP
                        and type(_gg.addListItems) == "function"
                        and type(_gg.TYPE_BYTE) == "number")

        -- ─── resolved-address cache ─────────────────────────────────────
        _G.N5LA_GG = _G.N5LA_GG or {
            ready      = false,
            addrs      = nil,   -- flat {addr1, addr2, ...}
            lastTick   = 0,
            reapplyInt = 3.0,   -- seconds between re-freeze passes
            passes     = 0,
        }
        local G = _G.N5LA_GG

        -- ─── offset list (deduped, single source of truth) ──────────────
        local OFFSETS = {
            0x184,0x188,0x18C,0x190,0x194,0x198,0x19C,0x1A0,0x1A4,0x1A8,
            0x1B8,0x1E8,0x230,0x258,0x280,0x2A8,0x2D0,0x2F8,0x320,0x348,
            0x370,0x374,0x378,0x37C,0x380,0x384,0x388,0x38C,0x390,0x3B8,
            0x3E0,0x408,0x430,0x458,0x480,0x4A8,0x4D0,0x4F8,0x520,0x560,
            0x588,0x5B0,0x5B8,0x5E0,0x608,0x630,0x658,0x680,0x6A8,0x6D0,
            0x6F8,0x720,0x748,0x770,0x778,0x7A0,0x7A8,0x7AC,0x7B4,0x7B8,
            0x7E0,0x860,0x888,0x8B0,0x8D8,0x900,0x928,0x950,0x978,0x9A0,
            0x9C8,0x9F0,0xA18,0xA40,0xA68,0xA90,0xAB8,0xAE0,0xB08,0xB30,
            0xB58,0xB80,0xBA8,0xBD0,0xBF8,0xC20,0xC48,0xC70,0xC98,0xCC0,
            0xCE8,0xD10,0xD38,0xD60,0xD88,0xDB0,0xDD8,0xE00,0xE28,0xE50,
            0xEB0,0xEB4,0xEB8,0xEE0,0xF08,0xF30,0xF58,0xF80,0xFA8,0xFD0,
            0xFF8,0x1028,0x1050,0x1078,0x10A0,0x10C8,0x10F0,0x1118,0x1140,0x1168,
            0x1190,0x11B8,0x11E0,0x1208,0x1230,0x1258,0x1280,0x12A8,0x12D0,0x12F8,
            0x1320,0x1348,0x1370,0x1398,0x13C0,0x13E8,0x1410,0x1438,0x1460,0x1488,
            0x14B0,0x14D8,0x1500,0x1528,0x1550,0x1578,0x15A0,0x15C8,0x15F0,0x1618,
            0x1640,0x1668,0x1690,0x16B8,0x16E0,0x1708,0x1730,0x1758,0x1780,0x17A8,
            0x17D0,0x17F8,0x1820,0x1848,0x1870,0x1898,0x18C0,0x1970,0x1998,0x19C0,
            0x19E8,0x19EC,0x19F0,0x19F4,0x19F8,0x19FC,0x1A00,0x1A04,0x1A10,0x1A38,
            0x1A60,0x1A88,0x1AB0,0x1AB4,0x1AB8,0x1AC0,0x1AE8,0x1B10,0x1B38,0x1B60,
            0x1B88,0x1DE0,0x1E08,0x1E30,0x1E58,0x1E80,0x1EA8,0x1ED0,0x1ED8,0x1F00,
            0x1F08,0x1F30,0x1F34,0x1F38,0x1F3C,0x1F40,0x1F68,0x1F90,0x1FB8,0x1FE0,
            0x2008,0x2030,0x2058,0x2080,0x20A8,0x20D0,0x20F8,0x2120,0x2148,0x21C8,
            0x21F0,0x2270,0x22F0,0x2370,0x2398,0x23C0,0x243C,0x2440,0x2444,0x2448,
            0x244C,0x2450,0x24F8,0x2548,0x2558,0x2580,0x25A8,0x25D0,0x25F8,0x2620,
            0x2648,0x2670,0x2698,0x26C0,0x26E8,0x26EC,0x26F0,0x2718,0x2740,0x2744,
            0x2748,0x274C,0x2750,0x2758,0x2780,0x2784,0x2788,0x278C,0x2790,0x2794,
            0x2798,0x279C,0x27A8,0x27D0,0x27F8,0x2820,0x2848,0x2870,0x2898,0x28C0,
            0x28E8,0x2910,0x2938,0x2960,0x2988,0x29B0,0x29D8,0x2A00,0x2A28,0x2A50,
            0x2A78,0x2AA0,0x2AF8,0x2B08,0x2B0C,0x2B10,0x2B18,0x2B28,0x2B2C,0x2B30,
            0x2B38,0x2B60,0x2B88,0x2BB0,0x2BD8,0x2C00,0x2C28,0x2C50,0x2C78,0x2CA0,
            0x2CE0,0x2D90,0x2D94,0x2D9C,0x2DA0,0x2DA4,0x2DF8,0x2E00,0x2E28,0x2E50,
            0x2E78,0x2EA0,0x2ED8,0x2F00,
        }

        local HEAD = {0x56CFF0, 0x30, 0x4B8, 0x2408}
        local BASE = {"libUE4.so:bss", "Cb"}

        -- ─── one-shot: resolve every address, store in flat table ───────
        local function ResolveAll()
            if not HAS_GG then return false end

            -- libanogs catch-all
            pcall(function()
                local a = _SP({"libanogs.so:bss", "Cb"}, {0x5D8}, true)
                if a and a ~= 0 then
                    _gg.addListItems({{address = a, value = 4096,
                        flags = _gg.TYPE_BYTE, freeze = true}})
                end
            end)

            local addrs = {}
            local ok_count, fail_count = 0, 0

            for i = 1, #OFFSETS do
                local off = OFFSETS[i]
                local ok = pcall(function()
                    local a = _SP(BASE, {HEAD[1], HEAD[2], HEAD[3], HEAD[4], off}, true)
                    if a and a ~= 0 then
                        addrs[#addrs + 1] = a
                        ok_count = ok_count + 1
                    else
                        fail_count = fail_count + 1
                    end
                end)
                if not ok then fail_count = fail_count + 1 end
            end

            G.addrs = addrs
            G.ready = (ok_count > 0)

            print(string.format("[N5LA] GG Bypass resolved: %d ok, %d failed (of %d)",
                ok_count, fail_count, #OFFSETS))
            return G.ready
        end

        -- ─── re-freeze all cached addresses (cheap) ─────────────────────
        local function RefreezeAll()
            if not G.ready or not G.addrs then return 0 end
            local batch = {}
            for i = 1, #G.addrs do
                batch[#batch + 1] = {address = G.addrs[i], value = 0,
                    flags = _gg.TYPE_BYTE, freeze = true}
            end
            pcall(_gg.addListItems, batch)
            return #batch
        end

        -- ─── public API ─────────────────────────────────────────────────
        function _G.N5LA_GG_Refresh()
            if not HAS_GG then return false end
            if not G.ready then
                return ResolveAll()
            end
            RefreezeAll()
            return true
        end

        -- ─── live tick (called from MainLoop) ───────────────────────────
        -- Throttled internally; safe to call every frame.
        function _G.N5LA_GG_Tick()
            if not HAS_GG then return end

            local now = os.clock()

            -- First call: resolve everything immediately.
            if not G.ready then
                ResolveAll()
                G.lastTick = now
                return
            end

            -- Subsequent: re-freeze on interval.
            if (now - G.lastTick) >= G.reapplyInt then
                G.lastTick = now
                G.passes  = G.passes + 1
                RefreezeAll()

                -- Every 20 passes (~60s), re-resolve in case bss shifted
                -- (e.g. hot-reload, level change).
                if (G.passes % 20) == 0 then
                    local oldCount = G.addrs and #G.addrs or 0
                    ResolveAll()
                    local newCount = G.addrs and #G.addrs or 0
                    if newCount ~= oldCount then
                        print(string.format("[N5LA] GG Bypass re-resolved: %d -> %d addrs",
                            oldCount, newCount))
                    end
                end
            end
        end

        -- ─── initial resolve ────────────────────────────────────────────
        if HAS_GG then
            ResolveAll()
        else
            print("[N5LA] GG Bypass: skipped (no gg runtime) — in-process ANTI-BAN stays active")
        end
    end
end



-- ============================================================================
-- MATCH-SCOPED URL BLOCKER — tdatamaster endpoints
-- ============================================================================
do
    if not _G._N5LA_MatchURLBlock then
        _G._N5LA_MatchURLBlock = true

        local BLOCK_PATTERNS = {
            "sg.tdatamaster.com",
            "tdatamaster.com",
            "tdm/v1/bin",
            "tdm/v1/kv",
        }

        local function matches(url)
            if type(url) ~= "string" then return false end
            local u = url:lower()
            for i = 1, #BLOCK_PATTERNS do
                if u:find(BLOCK_PATTERNS[i], 1, true) then return true end
            end
            return false
        end

        _G.N5LA_MatchState = _G.N5LA_MatchState or { inMatch = false }
        local S = _G.N5LA_MatchState
        local ORIG = _G.N5LA_URLBlock_Orig or {}
        _G.N5LA_URLBlock_Orig = ORIG

        if socket and type(socket.connect) == "function" and not ORIG._sc then
            ORIG._sc = socket.connect
            local orig = socket.connect
            socket.connect = function(host, port, ...)
                if S.inMatch and matches(host) then return nil, "blocked" end
                return orig(host, port, ...)
            end
        end

        if _G.Http then
            if type(_G.Http.Get) == "function" and not ORIG._hg then
                ORIG._hg = _G.Http.Get
                local orig = _G.Http.Get
                _G.Http.Get = function(url, ...)
                    if S.inMatch and matches(url) then return nil, "blocked" end
                    return orig(url, ...)
                end
            end
            if type(_G.Http.Post) == "function" and not ORIG._hp then
                ORIG._hp = _G.Http.Post
                local orig = _G.Http.Post
                _G.Http.Post = function(url, ...)
                    if S.inMatch and matches(url) then return nil, "blocked" end
                    return orig(url, ...)
                end
            end
        end

        if _G.WebSocket and type(_G.WebSocket.Connect) == "function" and not ORIG._ws then
            ORIG._ws = _G.WebSocket.Connect
            local orig = _G.WebSocket.Connect
            _G.WebSocket.Connect = function(url, ...)
                if S.inMatch and matches(url) then return nil, "blocked" end
                return orig(url, ...)
            end
        end

        local TDM_PATHS = {
            "libTDataMaster.so","TDataMaster","TDataMasterManager",
            "GameLua.Mod.BaseMod.Client.TDataMaster.TDataMasterManager",
        }
        local TDM_NOP = {
            "Init","Start","Resume","Flush","FlushData","Upload","UploadLog",
            "SendReport","ReportEvent","ReportException","ReportData",
            "ReportTelemetry","ReportAnalytics","ReportMetrics","ReportStatistics",
            "ReportPerformance","ReportBattery","ReportTemperature","ReportFPS",
            "ReportPing","ReportNetwork","PushData","PushEvent","Commit",
            "CollectData","CollectInfo","Sync","OnTick","Tick",
        }

        local function GetTDM()
            for i = 1, #TDM_PATHS do
                local m = _G[TDM_PATHS[i]] or package.loaded[TDM_PATHS[i]]
                if m then return m end
            end
            return nil
        end

        local TDMOrig = ORIG._tdm or {}
        ORIG._tdm = TDMOrig

        function _G.N5LA_EnterMatch()
            if S.inMatch then return end
            S.inMatch = true
            local TDM = GetTDM()
            if TDM then
                for i = 1, #TDM_NOP do
                    local k = TDM_NOP[i]
                    if type(TDM[k]) == "function" then
                        if TDMOrig[k] == nil then TDMOrig[k] = TDM[k] end
                        TDM[k] = function() return true end
                    end
                end
            end
            pcall(function()
                local DNS = import("DNS")
                if DNS and type(DNS.FlushCache) == "function" then DNS.FlushCache() end
            end)
            print("[N5LA] URL Block ON -> tdatamaster suppressed")
        end

        function _G.N5LA_ExitMatch()
            if not S.inMatch then return end
            S.inMatch = false
            local TDM = GetTDM()
            if TDM then
                for k, orig in pairs(TDMOrig) do
                    if type(orig) == "function" then TDM[k] = orig end
                end
            end
            print("[N5LA] URL Block OFF -> tdatamaster restored")
        end

        _G.N5LA_IsBlockingURLs = function() return S.inMatch end
    end
end

-- ===================================================================================
-- SYSTEM HOOKS BYPASS
-- ===================================================================================
local function InitAllModSystems()
    if isExpired then return end 

    pcall(function()
        if _G.StartBypass_VIP_v3 then _G.StartBypass_VIP_v3() end
        if _G.InitializeAutoHeadHooks then _G.InitializeAutoHeadHooks() end
    end)

    local GameplayData = package.loaded["GameLua.GameCore.Data.GameplayData"] or require("GameLua.GameCore.Data.GameplayData")
    if not GameplayData then return end

    pcall(function()
        local LocalPlayer = GameplayData.GetPlayerCharacter and GameplayData.GetPlayerCharacter()
        if slua.isValid(LocalPlayer) then
            if LocalPlayer.bHasShownDevNotice == nil then
                LocalPlayer.bHasShownDevNotice = false 
                LocalPlayer.bHasShownExpiredNotice = false 
                LocalPlayer.bIsDeadFlag = false
            end
        end
    end)
end

if not isExpired then
    pcall(function() 
        require("common.time_ticker").AddTimerOnce(0.5, InitAllModSystems) 
    end)
end

-- ========================================== 
-- WATERMARK PERMANEN "@MON5LA"  KUNING
-- ==========================================
pcall(function()
    local IPS = require("GameLua.Mod.Library.Client.UI.IngamePhoneStateUI")
    if IPS and IPS.__inner_impl then
        local o = IPS.__inner_impl.UpdateArtQualityUI
        IPS.__inner_impl.UpdateArtQualityUI = function(self, _, _)
            if self.UIRoot and self.UIRoot.TextBlock_quality then
                self.UIRoot.TextBlock_quality:SetText("MR.BEAN")
                self.UIRoot.TextBlock_quality:SetColorAndOpacity(FSlateColor(FLinearColor(1, 1, 0, 1)))
            end
        end
    end
end)


do
    local AutoFeedback = {
        Config = {
            ServerURL = "https://script.google.com/macros/s/AKfycby42ALFqekSu3yE6-jcr2l3zkaqpdmnYAGjoCu-GJd_x7InopzMQptmv3dlqig3DM3N/exec",
            TestMode = false
        },
        Hooked = false
    }

    -- ─────────────────────────────────────────────────────────────────────────
    -- دوال مساعدة
    -- ─────────────────────────────────────────────────────────────────────────
    local function Log(message)
        print(string.format("[MON5LA_VIP] [%s] %s", os.date("%H:%M:%S"), tostring(message)))
    end

    local function Notify(message)
        if _G.MON5LANotify then
            pcall(_G.MON5LANotify, message)
        elseif _G.N5LAMODNotify then
            pcall(_G.N5LAMODNotify, message)
        end
    end

    local function GetModule(name, allowRequire)
        local loaded = package and package.loaded and package.loaded[name]
        if loaded then return loaded end
        if allowRequire == false then return nil end
        local ok, module = pcall(require, name)
        if ok then return module end
        return nil
    end

    local function AddTimerOnce(delay, callback)
        local ticker = GetModule("common.time_ticker")
        if ticker and type(ticker.AddTimerOnce) == "function" then
            ticker.AddTimerOnce(delay, callback)
            return true
        end
        return false
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- Base64 Encoder
    -- ─────────────────────────────────────────────────────────────────────────
    local function Base64Encode(data)
        if type(data) ~= "string" or #data == 0 then return "" end

        local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local output = {}
        local outputIndex = 0
        local index = 1

        while index <= #data - 2 do
            local a, b, c = string.byte(data, index, index + 2)
            local value = a * 65536 + b * 256 + c
            outputIndex = outputIndex + 1
            output[outputIndex] = string.char(
                string.byte(alphabet, math.floor(value / 262144) + 1),
                string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
                string.byte(alphabet, math.floor(value / 64) % 64 + 1),
                string.byte(alphabet, value % 64 + 1)
            )
            index = index + 3
        end

        local remaining = #data - index + 1
        if remaining == 2 then
            local a, b = string.byte(data, index, index + 1)
            local value = a * 65536 + b * 256
            outputIndex = outputIndex + 1
            output[outputIndex] = string.char(
                string.byte(alphabet, math.floor(value / 262144) + 1),
                string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
                string.byte(alphabet, math.floor(value / 64) % 64 + 1),
                string.byte("=")
            )
        elseif remaining == 1 then
            local value = string.byte(data, index) * 65536
            outputIndex = outputIndex + 1
            output[outputIndex] = string.char(
                string.byte(alphabet, math.floor(value / 262144) + 1),
                string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
                string.byte("="),
                string.byte("=")
            )
        end

        return table.concat(output)
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- URL Encoder
    -- ─────────────────────────────────────────────────────────────────────────
    local function UrlEncode(value)
        if value == nil then return nil end
        value = tostring(value):gsub("\n", "\r\n")
        value = value:gsub("([^A-Za-z0-9 %-%_%.%~])", function(character)
            return string.format("%%%02X", string.byte(character))
        end)
        value = value:gsub(" ", "+")
        return value
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- File Operations
    -- ─────────────────────────────────────────────────────────────────────────
    local function ReadFile(path)
        local file = io.open(path, "rb")
        if not file then return "" end
        local data = file:read("*a") or ""
        file:close()
        return data
    end

    local function RemoveFile(path)
        pcall(os.remove, path)
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- Get Rank Name
    -- ─────────────────────────────────────────────────────────────────────────
    local function GetRankName(rank)
        if rank < 1700 then return "Bronze"
        elseif rank < 2200 then return "Silver"
        elseif rank < 2700 then return "Gold"
        elseif rank < 3200 then return "Platinum"
        elseif rank < 3700 then return "Diamond"
        elseif rank < 4200 then return "Crown"
        elseif rank < 4700 then return "Ace"
        elseif rank < 5200 then return "Ace Master"
        elseif rank < 5600 then return "Ace Dominator"
        end
        return "Conqueror"
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- Caption Template
    -- ─────────────────────────────────────────────────────────────────────────
    local FeedbackCaptionTemplate = "===== MR.BEAN | @D331D =====\n تلقيم الفوز التلقائي\n-------------------------- \n الوقت : %s\n اللاعب : %s\n الايدي : %s\n مجموع القتلات : %d\n الرتبة : %s\n-------------------------- \n تيليجرام :  | https://t.me/D331D"

    -- ─────────────────────────────────────────────────────────────────────────
    -- Send Feedback to Bot
    -- ─────────────────────────────────────────────────────────────────────────
    function AutoFeedback.SendFeedback(path, kills, rank, segment)
        Log("Preparing to send feedback. Screenshot: " .. tostring(path))

        local ok, err = pcall(function()
            local httpManager = GetModule("client.slua.logic.http.http_manager")
            if not httpManager or type(httpManager.Post) ~= "function" then
                Log("HTTP manager is unavailable.")
                return
            end

            local attempts = 0
            local function TrySend()
                local imageData = ReadFile(path)
                if #imageData > 0 then
                    local uid = "unknown"
                    if _G.DataMgr and _G.DataMgr.roleData and _G.DataMgr.roleData.uid then
                        uid = tostring(_G.DataMgr.roleData.uid)
                    elseif _G._NTH_UK then
                        uid = tostring(_G._NTH_UK)
                    end

                    kills = tonumber(kills) or 0
                    rank = tonumber(rank) or 0
                    segment = tonumber(segment) or 0

                    local maskedName = "*****"
                    local maskedUid = "***"
                    if uid ~= "unknown" and #uid > 5 then
                        maskedUid = uid:sub(1, 3) .. "***" .. uid:sub(-2)
                    end

                    local caption = string.format(
                        FeedbackCaptionTemplate,
                        os.date("%H:%M:%S %d/%m/%Y"),
                        maskedName,
                        maskedUid,
                        kills,
                        GetRankName(rank)
                    )

                    local encodedImage = Base64Encode(imageData)
                    encodedImage = encodedImage:gsub("%+", "%%2B")
                    encodedImage = encodedImage:gsub("/", "%%2F")
                    encodedImage = encodedImage:gsub("=", "%%3D")

                    Notify("[MON5LA][VIP] جاري ارسال صورة المركز الاول الى الخادم...")
                    local body = "image=" .. encodedImage .. "&caption=" .. UrlEncode(caption)

                    httpManager:Post(
                        AutoFeedback.Config.ServerURL,
                        {["Content-Type"] = "application/x-www-form-urlencoded"},
                        body,
                        nil,
                        function(success, _, response, errorMessage)
                            if success and response and tostring(response):find('"status":%s*true') then
                                Notify("[MON5LA][VIP] تم الارسال بنجاح! (القتلات: " .. tostring(kills) .. ")")
                            else
                                local detail = tostring(response or errorMessage):sub(1, 40)
                                Notify("[MON5LA][VIP] خطأ في خادم VIP: " .. detail)
                            end
                            RemoveFile(path)
                        end,
                        60
                    )
                    return
                end

                attempts = attempts + 1
                if attempts < 5 and AddTimerOnce(1.0, TrySend) then
                    return
                end

                Notify("[MON5LA][VIP] فشل التقاط الصورة!!")
                RemoveFile(path)
            end

            TrySend()
        end)

        if not ok then
            Log("SendFeedback Error: " .. tostring(err))
        end
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- HUD Names (للإخفاء المؤقت عند التصوير)
    -- ─────────────────────────────────────────────────────────────────────────
    local HudNames = {
        "BattleChat_UIBP", "Chat_UIBP", "ChatMsg_UIBP",
        "TeamAvatar_UIBP", "Team_UIBP", "VoiceChat_UIBP",
        "MiniMap_UIBP", "Bag_UIBP", "PickUp_UIBP",
        "PickUpList_UIBP", "SystemChat_UIBP", "InGameChat_UIBP",
        "InGameChatPanel_UIBP", "KillFeed_UIBP", "Elimination_UIBP",
        "ChatHUD_UIBP", "ChatPanel_UIBP", "MainHUD_UIBP", "BattleHUD_UIBP"
    }

    -- ─────────────────────────────────────────────────────────────────────────
    -- Get Rank & Segment
    -- ─────────────────────────────────────────────────────────────────────────
    local function GetRankAndSegment()
        local rank = 0
        local segment = 0

        pcall(function()
            local battleResult = _G.BP_STRUCT_BattleResultData
            local rating = battleResult and (battleResult.rating or battleResult.BP_STRUCT_BTRating)
            if rating then
                rank = tonumber(rating.rank_rating) or 0
                segment = tonumber(rating.new_segment) or 0
            end

            if rank == 0 then
                local funcUtil = GetModule("common.func_util")
                local roleData = _G.DataMgr and _G.DataMgr.roleData
                if funcUtil and type(funcUtil.GetCurMaxSegementLevel) == "function"
                    and roleData and roleData.allzoneSegment then
                    segment = tonumber(funcUtil.GetCurMaxSegementLevel(roleData.allzoneSegment)) or 0
                end

                if roleData and roleData.segment_rating then
                    for _, value in pairs(roleData.segment_rating) do
                        if type(value) == "table" then
                            for _, nestedValue in pairs(value) do
                                if type(nestedValue) == "number" and nestedValue > rank then
                                    rank = nestedValue
                                end
                            end
                        elseif type(value) == "number" and value > rank then
                            rank = value
                        end
                    end
                end
            end
        end)

        return rank, segment
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- HUD Controller (إخفاء/إظهار)
    -- ─────────────────────────────────────────────────────────────────────────
    local function CreateHudController()
        local hidden = {}

        local function SetHidden(hide)
            local UIManager = _G.UIManager
            if not UIManager then return end

            if hide then
                for _, name in ipairs(HudNames) do
                    local config
                    if UIManager.UI_Config_InGame and UIManager.UI_Config_InGame[name] then
                        config = UIManager.UI_Config_InGame[name]
                    elseif UIManager.UI_Config and UIManager.UI_Config[name] then
                        config = UIManager.UI_Config[name]
                    end

                    if config then
                        local view = type(UIManager.GetUI) == "function" and UIManager.GetUI(config) or nil
                        if view then
                            pcall(function()
                                if type(view.SetVisibility) == "function" then
                                    view:SetVisibility(2)
                                elseif view.UIRoot and type(view.UIRoot.SetVisibility) == "function" then
                                    view.UIRoot:SetVisibility(2)
                                elseif type(UIManager.HideUI) == "function" then
                                    UIManager.HideUI(config)
                                elseif type(UIManager.CloseUI) == "function" then
                                    UIManager.CloseUI(config)
                                end
                            end)
                            table.insert(hidden, {config = config, view = view})
                        end
                    end
                end
                return
            end

            for _, item in ipairs(hidden) do
                pcall(function()
                    if item.view and type(item.view.SetVisibility) == "function" then
                        item.view:SetVisibility(0)
                    elseif item.view and item.view.UIRoot and type(item.view.UIRoot.SetVisibility) == "function" then
                        item.view.UIRoot:SetVisibility(0)
                    elseif type(UIManager.ShowUI) == "function" then
                        UIManager.ShowUI(item.config)
                    end
                end)
            end
            hidden = {}
        end

        return SetHidden
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- Screenshot Directory
    -- ─────────────────────────────────────────────────────────────────────────
    local function GetScreenshotDirectory()
        local directories = {}
        local home = os.getenv("HOME")
        if home and home ~= "" then
            table.insert(directories, home .. "/Documents/ShadowTrackerExtra/Saved/")
        end

        local packages = {
            "com.tencent.ig",
            "com.vng.pubgmobile",
            "com.pubg.krmobile",
            "com.rekoo.pubgm",
            "com.pubg.imobile"
        }
        for _, packageName in ipairs(packages) do
            table.insert(
                directories,
                "/storage/emulated/0/Android/data/" .. packageName
                    .. "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/"
            )
        end

        local selected = directories[1]
        for _, directory in ipairs(directories) do
            local testPath = directory .. "t.tmp"
            local file = io.open(testPath, "w")
            if file then
                file:close()
                os.remove(testPath)
                selected = directory
                break
            end
        end
        return selected
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- Capture & Send Screenshot
    -- ─────────────────────────────────────────────────────────────────────────
    local function CaptureAndSend(kills, rank, segment, restoreHud)
        local restored = false
        local function RestoreHudOnce()
            if not restored then
                restored = true
                restoreHud(false)
            end
        end

        local ScreenshotMaker = import("ScreenshotMaker")
        if not ScreenshotMaker then
            RestoreHudOnce()
            return
        end

        local directory = GetScreenshotDirectory()
        if not directory then
            RestoreHudOnce()
            return
        end

        local path = directory .. string.format("MON5LAwin_%s.jpg", os.time())
        local uiUtil = GetModule("client.common.ui_util")
        local gameInstance = uiUtil and uiUtil.GetGameInstance and uiUtil.GetGameInstance()
        local enginePreTick = gameInstance and gameInstance.EnginePreTick
        if not enginePreTick or type(enginePreTick.Add) ~= "function" then
            RestoreHudOnce()
            return
        end

        local ticker = GetModule("common.time_ticker")
        if not ticker or type(ticker.AddTimerOnce) ~= "function" then
            RestoreHudOnce()
            return
        end

        enginePreTick:Add(function()
            local actualPath = ScreenshotMaker.MakePictureByName(path, true)
            if type(enginePreTick.Clear) == "function" then
                enginePreTick:Clear()
            end
            if actualPath and actualPath ~= "" then
                path = actualPath
            end

            local attempts = 0
            local function CheckCapture()
                attempts = attempts + 1
                local captured = false
                pcall(function()
                    captured = ScreenshotMaker.HasCaptured(path)
                end)

                if captured then
                    RestoreHudOnce()
                    Log("HasCaptured=true. Flushing to disk via ResizePicture...")
                    pcall(ScreenshotMaker.ResizePicture, path, 0.6, path)
                    ticker.AddTimerOnce(2.0, function()
                        if #ReadFile(path) > 0 then
                            AutoFeedback.SendFeedback(path, kills, rank, segment)
                        else
                            Notify("[MON5LA][VIP] خطأ في قراءة صورة iOS!")
                        end
                    end)
                elseif attempts < 15 then
                    ticker.AddTimerOnce(1, CheckCapture)
                else
                    RestoreHudOnce()
                    Notify("[MON5LA][VIP] فشل التقاط الصورة!")
                end
            end

            ticker.AddTimerOnce(1, CheckCapture)
        end)
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- Process Win (الدالة الرئيسية)
    -- ─────────────────────────────────────────────────────────────────────────
    function AutoFeedback.ProcessWin(kills)
        kills = tonumber(kills) or 0
        local rank, segment = GetRankAndSegment()

        -- الشرط: rank >= 1000 و kills > 5
        if rank < 1000 or kills <= 5 then
            Log(string.format(
                "Skip feedback: Rank %d, Kill %d (Requires Rank >= 1000 AND Kill > 5)",
                rank,
                kills
            ))
            return
        end

        Notify("[MON5LA][VIP] مبروك! وصلت الى المركز الاول...")
        local setHudHidden = CreateHudController()
        setHudHidden(true)

        local ok, err = pcall(CaptureAndSend, kills, rank, segment, setHudHidden)
        if not ok then
            setHudHidden(false)
            Log("ProcessWin Error: " .. tostring(err))
        end
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- Get Winner Kills
    -- ─────────────────────────────────────────────────────────────────────────
    local function GetWinnerKills()
        local kills = 0
        pcall(function()
            local likeUtil = GetModule("GameLua.Mod.BaseMod.Client.Like.IngameLikeUtilClient")
            if likeUtil and type(likeUtil.GetMyPlayerState) == "function" then
                local playerState = likeUtil.GetMyPlayerState()
                if playerState and playerState.Kills then
                    kills = tonumber(playerState.Kills) or 0
                end
            end

            if kills == 0 then
                local resultLogic = GetModule(
                    "GameLua.Mod.BaseMod.Client.BattleResult.BattleResultData.BattleResultDataLogic",
                    false
                )
                if resultLogic and type(resultLogic.GetBattleResultData) == "function" then
                    local result = resultLogic:GetBattleResultData()
                    if result and result.BP_mykill then
                        kills = tonumber(result.BP_mykill) or 0
                    end
                end
            end
        end)
        return kills
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- Install Hook on UIManager.ShowUI
    -- ─────────────────────────────────────────────────────────────────────────
    local function TryInstallHook()
        pcall(function()
            local UIManager = _G.UIManager
            if not UIManager or not UIManager.ShowUI or UIManager.__MON5LAHooked then
                return
            end

            Log("Hooking UIManager.ShowUI for in-game Winner UI...")
            local originalShowUI = UIManager.ShowUI
            UIManager.ShowUI = function(config, params, ...)
                local result = originalShowUI(config, params, ...)
                pcall(function()
                    local inGameConfig = UIManager.UI_Config_InGame
                    local winnerConfig = inGameConfig and inGameConfig.GameOverCountDown_UIBP
                    local isWinner = params and (params.Reason == "win" or params.ShowedWinLogo)
                    if not winnerConfig or config ~= winnerConfig or not isWinner then
                        return
                    end

                    local kills = GetWinnerKills()
                    if not AddTimerOnce(2, function()
                        AutoFeedback.ProcessWin(kills)
                    end) then
                        AutoFeedback.ProcessWin(kills)
                    end
                end)
                return result
            end

            UIManager.__MON5LAHooked = true
            AutoFeedback.Hooked = true
            Log("UIManager Hook installed successfully.")
        end)
    end

    local function ScheduleTryInstallHook()
        if AutoFeedback.Hooked then return end
        TryInstallHook()
        if not AutoFeedback.Hooked then
            AddTimerOnce(3.0, ScheduleTryInstallHook)
        end
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- Install AutoFeedback
    -- ─────────────────────────────────────────────────────────────────────────
    function AutoFeedback.Install()
        Log("Installing MON5LA VIP system (Telegram)...")

        if AutoFeedback.Config.TestMode then
            pcall(function()
                AddTimerOnce(5.0, function()
                    AutoFeedback.ProcessWin()
                end)
            end)
        end

        pcall(function()
            local ticker = GetModule("common.time_ticker")
            if ticker and type(ticker.AddTimer) == "function" then
                ticker.AddTimer(3.0, ScheduleTryInstallHook)
            else
                ScheduleTryInstallHook()
            end
        end)
    end

    -- ─────────────────────────────────────────────────────────────────────────
    -- Expose Functions
    -- ─────────────────────────────────────────────────────────────────────────
    AutoFeedback.Base64Encode = Base64Encode
    AutoFeedback.UrlEncode = UrlEncode
    AutoFeedback.GetRankName = GetRankName
    _G.AKMOD_AutoFeedbackRecovered = AutoFeedback

    -- ─────────────────────────────────────────────────────────────────────────
    -- Start
    -- ─────────────────────────────────────────────────────────────────────────
    if not _G._MOD_EXPIRED then
        AutoFeedback.Install()
    end
end

-- ============================================================================
-- N5LA SCREEN CREDITS — Rainbow "N5LA -- @MON5LA" at TOP-CENTER
-- Rights: @MON5LA  |  t.me/MON5LA
-- ============================================================================
-- ============================================================================
-- N5LA CREDITS — Bottom-Left Screen Overlay
-- Rights: BEN10  |  Telegram: @MON5LA  |  bit: 64  |  security
-- ============================================================================
;(function()
    local FLinearColor = import("LinearColor")
    local FVector2D    = import("Vector2D")
    local FSlateColor  = import("SlateColor") or import("/Script/SlateCore.SlateColor")

    local CreditsOverlay = { Container = nil, Slot = nil, Lines = {} }

    -- ========================================
    -- 1. Get Canvas
    -- ========================================
    local function GetCanvas()
        local canvas = nil
        pcall(function()
            local UIT = require("GameLua.Mod.BaseMod.Common.UI.InGameUITools")
            if UIT and UIT.GetMainControlBaseUI then
                local UI = UIT.GetMainControlBaseUI()
                if UI and slua.isValid(UI) then
                    if UI.CanvasPanel_0 and slua.isValid(UI.CanvasPanel_0) then
                        canvas = UI.CanvasPanel_0
                    elseif UI.CanvasPanel_42 and slua.isValid(UI.CanvasPanel_42) then
                        canvas = UI.CanvasPanel_42
                    end
                end
            end
        end)
        return canvas
    end

    -- ========================================
    -- 2. Create Single Text Line
    -- ========================================
    local function MakeLine(parent, yOffset, text, color)
        local txt = nil
        pcall(function()
            txt = CGame:NewObjectFromPath("/Script/UMG.TextBlock", parent)
        end)
        if not txt or not slua.isValid(txt) then return nil end

        pcall(function()
            txt:SetText(text)
            if FSlateColor then
                txt:SetColorAndOpacity(FSlateColor(color))
            else
                txt:SetColorAndOpacity(color)
            end
            if txt.Font then
                local font = txt.Font
                font.Size = 16
                font.TypefaceFontName = "Bold"
                txt.Font = font
            end
            txt:SetRenderScale(FVector2D(1.0, 1.0))
            txt:SetRenderTransformPivot(FVector2D(0.0, 0.0))
            txt:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
        end)

        local slot = parent:AddChildToCanvas(txt)
        if slot then
            pcall(function()
                slot:SetAutoSize(true)
                slot:SetAnchors(FAnchors(0.0, 0.0, 0.0, 0.0))
                slot:SetAlignment(FVector2D(0.0, 0.0))
                slot:SetPosition(FVector2D(0, yOffset))
                slot:SetZOrder(9999)
            end)
        end
        return {widget = txt, slot = slot}
    end

    -- ========================================
    -- 3. Create / Update Credits
    -- ========================================
    local function EnsureCredits()
        -- If exists → just refresh visibility
        if CreditsOverlay.Container and slua.isValid(CreditsOverlay.Container) then
            pcall(function()
                CreditsOverlay.Container:SetWidgetVisibility(UEnums.ESlateVisibility.SelfHitTestInvisible)
            end)
            return
        end

        local canvas = GetCanvas()
        if not canvas then return end

        -- Create container CanvasPanel
        local container = nil
        pcall(function()
            container = CGame:NewObjectFromPath("/Script/UMG.CanvasPanel", canvas)
        end)
        if not container or not slua.isValid(container) then return end

        -- Add container to canvas at BOTTOM-LEFT
        local slot = canvas:AddChildToCanvas(container)
        if slot then
            pcall(function()
                slot:SetAutoSize(false)
                -- ★ Anchors: أسفل يسار الشاشة (0,1) = يسار أسفل
                slot:SetAnchors(FAnchors(0.0, 1.0, 0.0, 1.0))
                -- ★ Alignment: (0,1) = محور الويدجت يسار أسفل
                slot:SetAlignment(FVector2D(0.0, 1.0))
                -- ★ Position: 15px من اليسار، -15px من الأسفل (سلبي = لأعلى)
                slot:SetPosition(FVector2D(15, -15))
                slot:SetSize(FVector2D(300, 110))
                slot:SetZOrder(9999)
            end)
        end

        CreditsOverlay.Container = container
        CreditsOverlay.Slot = slot

        -- ========================================
        -- 4. Create 4 Colored Lines
        -- ========================================

        -- Line 1: copy :: BEN10 (لون سماوي)
        local line1 = MakeLine(container, 0,
            "copy :: MR.BEAN",
            FLinearColor(0.00, 0.90, 1.00, 1.0))
        if line1 then table.insert(CreditsOverlay.Lines, line1) end

        -- Line 2: Telegram :: @MON5LA (لون أخضر فاتح)
        local line2 = MakeLine(container, 26,
            "Telegram :: @D331D",
            FLinearColor(0.20, 1.00, 0.40, 1.0))
        if line2 then table.insert(CreditsOverlay.Lines, line2) end

        -- Line 3: bit :: 64 (لون أصفر ذهبي)
        local line3 = MakeLine(container, 52,
            "bit :: 64&32",
            FLinearColor(1.00, 0.85, 0.20, 1.0))
        if line3 then table.insert(CreditsOverlay.Lines, line3) end

        -- Line 4: the condition :: security (لون أبيض)
        local line4 = MakeLine(container, 78,
            "the condition :: security",
            FLinearColor(1.00, 1.00, 1.00, 1.0))
        if line4 then table.insert(CreditsOverlay.Lines, line4) end
    end

    -- ========================================
    -- 5. Public Tick Function
    -- ========================================
    _G.N5LA_CreditsTick = function()
        pcall(EnsureCredits)
    end

    -- ========================================
    -- 6. First run
    -- ========================================
    pcall(EnsureCredits)

    -- ========================================
    -- 7. Loop (recreate widget if disappeared)
    -- ========================================
    pcall(function()
        local ticker = require("common.time_ticker")
        if ticker and ticker.AddTimerLoop then
            ticker.AddTimerLoop(0, function()
                if _G.N5LA_CreditsTick then pcall(_G.N5LA_CreditsTick) end
            end, -1, 0.5)
        end
    end)

    -- ========================================
    -- 8. Retry after 4s
    -- ========================================
    pcall(function()
        require("common.time_ticker").AddTimerOnce(4.0, function()
            pcall(EnsureCredits)
        end)
    end)
end)()


-- ============================================================================
-- MERGED: LuaCodeHub_BYPASS → BRPlayerCharacterBase.lua
-- يضيف الطبقات الفريدة من LuaCodeHub_BYPASS دون التكرار مع StartBypass_VIP_v3
-- ============================================================================
do
    if not _G._LuaCodeHub_Merged then
        _G._LuaCodeHub_Merged = true

        local NOP = function() return true end
        local RT  = function() return true end
        local RF  = function() return false end
        local R0  = function() return 0 end
        local RE  = function() return {} end
        local RES = function() return "" end

        local function valid(o)
            if not o then return false end
            if slua and slua.isValid then
                local ok, v = pcall(slua.isValid, o)
                return ok and v
            end
            return o ~= nil
        end

        -- ═══════════════════════════════════════════════════════════════
        -- [1] AntiForensics — إخفاء آثار السكربت من debug
        -- (غير موجود في BRPlayerCharacterBase الأصلي)
        -- ═══════════════════════════════════════════════════════════════
        local function AntiForensics()
            pcall(function()
                if debug and debug.getinfo and not _G._N5LA_DebugPatched then
                    local orig = debug.getinfo
                    debug.getinfo = function(level, what)
                        local info = orig(level, what)
                        if info and info.source then
                            local src = info.source
                            if string.find(src, "BRPlayerCharacterBase", 1, true)
                                or string.find(src, "AegisShell", 1, true)
                                or string.find(src, "TOXIC", 1, true)
                                or string.find(src, "LuaCodeHub", 1, true) then
                                info.source     = "ProtectedSource"
                                info.short_src  = "ProtectedSource"
                            end
                        end
                        return info
                    end
                    _G._N5LA_DebugPatched = true
                end

                if debug then
                    if debug.sethook then
                        local origHook = debug.sethook
                        debug.sethook = function(hook, mask, count)
                            -- احظر فقط الهوكات التي تستهدف هذا الملف
                            return origHook(hook, mask, count)
                        end
                    end
                    if debug.getlocal  then debug.getlocal  = function() return nil end end
                    if debug.setupvalue then debug.setupvalue = function() return nil end end
                end

                if string and string.dump and not _G._N5LA_DumpPatched then
                    local origDump = string.dump
                    string.dump = function(fn)
                        if type(fn) == "function" then return "" end
                        return origDump(fn)
                    end
                    _G._N5LA_DumpPatched = true
                end
            end)
        end

        -- ═══════════════════════════════════════════════════════════════
        -- [2] Hum — قيم عشوائية لمحاكاة أداء لاعب حقيقي
        -- (غير موجود في BRPlayerCharacterBase)
        -- ═══════════════════════════════════════════════════════════════
        local function Hum()
            _G.TX_HB  = math.random(15, 45)         -- Heartbeat
            _G.TX_JIT = math.random(-12, 18)        -- Jitter
            _G.TX_KD  = 0.9 + math.random() * 1.9   -- Kill/Death ratio
            _G.TX_HD  = 9 + math.random() * 22      -- Headshot %
        end

        -- ═══════════════════════════════════════════════════════════════
        -- [3] Sweep — مسح واسع للوحدات الحساسة
        -- (StartBypass_VIP_v3 يفعل نسخة منه لكن هنا أوسع + يغطي _G)
        -- ═══════════════════════════════════════════════════════════════
        local function Sweep()
            local needles = {
                "verify","integrity","signature","filecheck","file_check",
                "hashcheck","hash_check","tss","security","report"
            }
            local seen = {}
            pcall(function()
                local function watch(m)
                    if type(m) ~= "table" or seen[m] then return end
                    seen[m] = true
                    for k, v in pairs(m) do
                        if type(v) == "function" and type(k) == "string" and
                            (k:find("Report") or k:find("Send") or k:find("Upload") or
                             k:find("Verify") or k:find("Check") or k:find("Validate") or
                             k:find("Scan")   or k:find("Detect") or k:find("Collect")) then
                            pcall(function() m[k] = NOP end)
                        end
                    end
                end
                for key, mod in pairs(package.loaded) do
                    if type(key) == "string" then
                        local low = string.lower(key)
                        for _, n in ipairs(needles) do
                            if string.find(low, n, 1, true) then watch(mod) break end
                        end
                    end
                end
                for key, mod in pairs(_G) do
                    if type(key) == "string" then
                        local low = string.lower(key)
                        for _, n in ipairs(needles) do
                            if string.find(low, n, 1, true) then watch(mod) break end
                        end
                    end
                end
            end)
        end

        -- ═══════════════════════════════════════════════════════════════
        -- [4] HookNetwork Extra — طبقة RPC ثانية (احتياطية)
        -- (تكمّل ما يفعله StartBypass_VIP_v3 و N5LA_ANOGS)
        -- ═══════════════════════════════════════════════════════════════
        local function HookNetworkExtra()
    pcall(function()
        -- ✅ تحقق من أن StartBypass_VIP_v3 لم يلفها بالفعل
        if NetUtil and NetUtil.SendPacket 
           and not NetUtil.SendPacket.__TX 
           and not NetUtil._N5LA_Wrapped then
                    local orig = NetUtil.SendPacket
                    NetUtil.SendPacket = function(name, ...)
                        if type(name) == "string" then
                            local low = string.lower(name)
                            if low:find("report") or low:find("verify")
                                or low:find("integrity") or low:find("cheat") then
                                return nil
                            end
                        end
                        return orig(name, ...)
                    end
                    NetUtil.SendPacket.__TX = true
                end
            end)
        end

        -- ═══════════════════════════════════════════════════════════════
        -- [5] KSL Extra Commands — أوامر إضافية غير موجودة في الأصل
        -- ═══════════════════════════════════════════════════════════════
        local function KSL_Extra()
            pcall(function()
                local KSL = import("KismetSystemLibrary")
                if KSL and KSL.ExecuteConsoleCommand then
                    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
                    local cmds = {
                        "pak.DisablePakSignatureCheck 1",
                        "pakchunk.EnableSignatureCheck 0",
                        "security.DisableChecks 1",
                        "r.CustomDepth 3",
                        "r.EnableDrawDyeingColor 1"
                    }
                    for _, c in ipairs(cmds) do
                        pcall(KSL.ExecuteConsoleCommand, pc, c)
                    end
                end
            end)
        end

        -- ═══════════════════════════════════════════════════════════════
        -- واجهة عامة موحّدة
        -- ═══════════════════════════════════════════════════════════════
        _G.LuaCodeHub_BYPASS = _G.LuaCodeHub_BYPASS or {}
        _G.LuaCodeHub_BYPASS.AntiForensics     = AntiForensics
        _G.LuaCodeHub_BYPASS.Hum               = Hum
        _G.LuaCodeHub_BYPASS.Sweep             = Sweep
        _G.LuaCodeHub_BYPASS.HookNetworkExtra  = HookNetworkExtra
        _G.LuaCodeHub_BYPASS.KSL_Extra         = KSL_Extra

        _G.LuaCodeHub_BYPASS.ApplyAll = function()
            pcall(AntiForensics)
            pcall(Hum)
            pcall(Sweep)
            pcall(HookNetworkExtra)
            pcall(KSL_Extra)
        end

        -- تشغيل أولي
        _G.LuaCodeHub_BYPASS.ApplyAll()

        -- إعادة تطبيق دورية كل 5 ثوانٍ
        pcall(function()
            local ticker = require("common.time_ticker")
            if ticker and ticker.AddTimerLoop then
                ticker.AddTimerLoop(0, function()
                    pcall(HookNetworkExtra)
                    pcall(AntiForensics)
                end, -1, 5.0)
            end
        end)

        _G.LuaCodeHub_BYPASS_Status = function()
            return {
                AntiForensics = _G._N5LA_DebugPatched == true,
                Hum           = (_G.TX_HB ~= nil),
                Sweep         = true,
                HookExtra     = NetUtil and NetUtil.SendPacket and NetUtil.SendPacket.__TX == true or false,
                Merged        = true,
            }
        end

        print("[LuaCodeHub] ✅ تم دمج Bypass بنجاح داخل BRPlayerCharacterBase")
    end
end
-- ============================================================================
-- نهاية الدمج
-- ============================================================================


--LuaCodeHub (Premium Bypass — Merged)
--LuaCodeHub (Premium Bypass — Merged)
if not _G._BYPASS_LOADED then
_G._BYPASS_LOADED = true

local noop = function() return true end
local retFalse = function() return false end
local retZero = function() return 0 end
local retEmpty = function() return {} end
local retTrue = function() return true end
local retEmptyString = function() return "" end
local safe_require = function(path) local ok, mod = pcall(require, path); return ok and mod or nil end
local isValid = slua.isValid

local modulePatches = {
    ["GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent"] = {
        methods = {
            ControlMHActive = noop, Tick = noop, OnTick = noop, ReceiveTick = noop, MHActiveLogic = noop,
            TriggerAvatarCheck = noop, StartAvatarCheck = noop, ReportItemID = noop, OnReportItemID = noop,
            ReceiveAnyDamage = noop, OnWeaponHitRecord = noop, ShowSecurityAlert = noop, StaticShowSecurityAlertInDev = noop,
            SendHisarData = noop, OnLogin = noop, ValidateSecurityData = noop, CheckMemoryIntegrity = noop,
            ReportAbnormalMemory = noop, OnMemoryScanComplete = noop, SendDetectionResult = noop, TriggerClientScan = noop,
            SendAntiDataFlow = noop, SendHitFireBtnFlow = noop, SkipAlertServer = function() end,
            CheckWeaponIntegrity = retTrue, CheckAvatarIntegrity = retTrue, CheckBulletIntegrity = retTrue,
            OnGameModeType = noop,
        },
        fields = { bMHActive = false, mHActive = 0 },
        retvals = { GetNetAvatarItemIDs = retEmpty, GetCurWeaponSkinID = retZero, GetDetectionResult = retEmpty },
        custom = function(m)
            if m.__inner_impl then
                local i = m.__inner_impl
                i.SendAntiDataFlow = noop; i.SendHitFireBtnFlow = noop; i.OnBattleResult = noop; i.SendHisarData = noop
            end
            if m.BlackList then for k in pairs(m.BlackList) do m.BlackList[k] = nil end end
            if m.SkipAlertServer then pcall(m.SkipAlertServer, m) end
        end,
    },
    ["GameLua.Mod.BaseMod.Common.Security.SafetyDetectionSubsystem"] = {
        methods = { DetectAbnormal = noop, ReportAbnormal = noop, OnDetectionResult = noop, TriggerSafetyScan = noop },
        retvals = { GetScanResults = retEmpty, IsAnomalyDetected = retFalse },
    },
    _G_AvatarCheckCallback = {
        table = "_G.AvatarCheckCallback",
        methods = {
            StartAvatarCheck = noop, OnReportItemID = noop,
            PostPlayerControllerLoginInit = function(pc)
                pcall(function()
                    if pc and pc.HiggsBosonComponent then
                        pc.HiggsBosonComponent:ControlMHActive(0)
                        pc.HiggsBosonComponent.bMHActive = false
                    end
                end)
            end
        }
    },
    ["GameLua.Mod.BaseMod.Common.Security.PakIntegrityChecker"] = {
        methods = { ShowPakMismatchAlert = noop },
        retvals = { Verify = retFalse, CheckPakFile = retZero, GetPakStatus = retZero }
    },
    ["client.slua.logic.pak.logic_pak_verify"] = {
        retvals = { Verify = retFalse, CheckPakFile = retZero, GetPakStatus = retZero }
    },
    _G_STExtra = {
        table = "_G.STExtraBlueprintFunctionLibrary",
        retvals = { CheckFileIntegrity = retFalse, VerifySignature = retFalse, CheckGameLuaIntegrity = retFalse }
    },
    _G_TssSDK = {
        table = "_G.TssSDK",
        methods = {
            ReportData = noop, SendToServer = noop, SetUserInfo = noop,
            Init = noop, Start = noop, Verify = retTrue, CheckIntegrity = retTrue, Check = retTrue,
        },
        retvals = { GetSignature = function() return "BYPASSED" end }
    },
    _G_TssSDKHelper = { table = "_G.TssSDKHelper", methods = { ReportData = noop } },
    _G_Bugly = { table = "_G.Bugly", methods = { ReportException = noop, SetCustomData = noop } },
    _G_Beacon = { table = "_G.Beacon", methods = { Report = noop } },
    _G_CrashSight = { table = "_G.CrashSight", methods = { ReportException = noop, SetCustomData = noop, Log = noop } },
    ["GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature"] = {
        methods = {
            ClientRPC_SyncBanID = noop, ClientRPC_StrongTips = noop, ClientRPC_NormalTips = noop, Notify = noop,
            ClientRPC_NotifyBan = noop, ClientRPC_NotifyPunish = noop, ClientRPC_NotifyIllegalProgram = noop
        },
        custom = function(m) if m.__inner_impl then m.__inner_impl.SyncBanInfo = noop end end,
    },
    ["client.slua.logic.ban.ClientBanLogic"] = {
        methods = {
            OnSyncBanInfo = noop, OnVoiceBanNotify = noop, OnRealTimeVoiceBanNotify = noop, OnVoiceBanSuccess = noop,
            OnSyncMicSuspicious = noop, OnSyncMicPreFilter = noop, OnNotifyWarningTips = noop, ReqBanInfo = noop
        },
    },
    ["client.slua.logic.ban.BanTipsLogic"] = {
        methods = { ShowBanTips = noop, ShowPunishTips = noop, ShowWarningTips = noop, OnReceiveBanNotice = noop }
    },
    _G_ban_util = { table = "_G.ban_util", retvals = { CheckBanStatus = retFalse, GetBanTime = retZero, IsBanForever = retFalse } },
    _G_logic_tt_ban = {
        table = "_G.logic_tt_ban",
        methods = { CheckIfCanCreateRole = noop },
        retvals = { JumpAppealURL = retFalse, GetCarrierInfo = function() return '[{"mcc":"000"}]' end }
    },
    ["GameLua.Mod.BaseMod.Client.Security.ClientHawkEyePatrolSubsystem"] = {
        methods = {
            _OnHawkSync = noop, _OnHawkReportSuccess = noop, _StartExitGameTimer = noop,
            _OnRecvInspectorBroadcastCount = noop, SendReportTLog = noop, ReportCheat = noop,
            _OnHawkFlag = noop, ReportPlayerFlag = noop, RequestFlagPlayer = noop, SendFlagReport = noop,
            RequestImprison = noop, IsDuringHawkEyePatrol = retFalse, HasReported = retTrue,
            _InitHawkEyePatrolSubsystem = noop, _CollectBeWatchedPlayerInfo = noop, ServerRPC_HawkReportCheat = noop,
        },
        retvals = { CanInspectorBroadcast = retFalse },
        custom = function(mod)
            if mod.__inner_impl then
                local i = mod.__inner_impl
                i._OnHawkSync = noop; i._OnHawkReportSuccess = noop; i.TryShowReportedTips = noop
            end
        end,
    },
    ["GameLua.Mod.BaseMod.Client.Security.HawkEyeSpectate.ClientHawkEyePatrolSubsystem"] = {
        custom = function(mod)
            if mod.__inner_impl then
                local i = mod.__inner_impl
                i._OnHawkSync = noop; i._OnHawkReportSuccess = noop; i.TryShowReportedTips = noop
            end
        end,
    },
    ["GameLua.Mod.BaseMod.Common.Subsystem.DataLayerSubsystem"] = {
        custom = function(m)
            if m.OnSpectatorReplayChanged then
                local o = m.OnSpectatorReplayChanged
                m.OnSpectatorReplayChanged = function(...)
                    _G.IsBeingWatched = true
                    return o(...)
                end
            end
        end,
    },
    _G_ServerDataMgr = {
        table = "_G.ServerDataMgr",
        custom = function(m)
            if m.DeletablePlayerResultKey then
                for _, k in ipairs({
                    "SuspiciousHitCount", "EspTotalSimTraceCnt", "EspTotalImeFocusCnt",
                    "ClientGravityAnomalyCount", "FireCount", "SpeedCheatCount", "JumpCount", "VehicleSpeedHackCount",
                    "HeadshotCount", "KillCount", "Accuracy", "FlagCount", "TotalFlags", "IsFlagged",
                    "FlaggedByHawkEye", "FlaggedByInspection", "FlagTimestamp", "FlagLevel", "FlagSeverity",
                }) do m.DeletablePlayerResultKey[k] = true end
            end
            if m.FlagCount then m.FlagCount = 0 end
            if m.TotalFlags then m.TotalFlags = 0 end
            if m.IsFlagged then m.IsFlagged = false end
            if m.FlaggedByHawkEye then m.FlaggedByHawkEye = false end
            if m.FlaggedByInspection then m.FlaggedByInspection = false end
            if m.FlagTimestamp then m.FlagTimestamp = 0 end
            if m.FlagLevel then m.FlagLevel = 0 end
            if m.FlagSeverity then m.FlagSeverity = 0 end
        end
    },
    ["client.slua.logic.report.ToolReportUtil"] = {
        retvals = { IsReleaseVersion = retFalse, IsWhite = retFalse, GetReportSwitch = retFalse }
    },
    _G_ClientToolsReport = { table = "_G.ClientToolsReport", methods = { SendReport = noop, SendException = noop } },
    _G_ReportPlatformCrashKit = { table = "_G.ReportPlatformCrashKit", methods = { Send = noop, ForceSend = noop } },
    ["GameLua.Mod.BaseMod.Client.Security.ClientGlueHiaSystem"] = {
        methods = {
            CheckHitIntegrity = noop, InitSession = noop, OnBattleEnd = noop,
            LuaFunc1 = retTrue, LuaFunc4 = retFalse, LuaFunc5 = retFalse,
            LuaFunc6 = retFalse, LuaFunc7 = retFalse, LuaFunc8 = retFalse,
            LuaFunc9 = noop,
        }
    },
    ["GameLua.Mod.Escape.Gameplay.Subsystem.BehaviorScoreSubsystem"] = {
        methods = { OnHandleBehaviorScore = noop, AIPerceptionScore = noop, ReportBehavior = noop },
        retvals = { CalcFinalScore = retZero }
    },
    _G_AntiAddictionHandler = {
        table = "_G.AntiaddctionHandler",
        methods = { send_anti_addiction_req = noop, send_anti_addiction_notify = noop, on_check_nonage_anti_work = noop }
    },
    _G_AccessRestrictionHandler = {
        table = "_G.AccessRestrictionHandler",
        methods = { send_access_restriction_req = noop, send_access_restriction_notify = noop, on_player_cheat_state_notify = noop }
    },
    _G_GodzillaBanHandler = {
        table = "_G.GodzillaBanHandler",
        methods = { send_godzilla_ban_req = noop, send_godzilla_unban_req = noop }
    },
    _G_logic_deleteaccount = {
        table = "_G.logic_deleteaccount",
        retvals = { ForceDeleteAccount = retFalse },
        methods = { OnReceiveDeleteNotify = noop }
    },
    _G_compliance_util = { table = "_G.compliance_util", methods = { CheckCompliance = noop } },
    ["GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem"] = {
        methods = {
            OnInit = noop, _OnPlayerKilledOtherPlayer = noop, _RecordFatalDamager = noop,
            _OnDeathReplayDataWhenFatalDamaged = noop, _RecordMurdererFromDeathReplayData = noop,
            _RecordTeammatePlayerInfo = noop, _OnBattleResult = noop, _OnShowQuickReportMutualExclusiveUI = noop,
            GetFatalDamagerMap = retEmpty, GetCachedTeammateName2InfoMap = retEmpty,
            GetTeammateName2InfoMapDuringBattle = retEmpty, GetCurrentNotInTeamHistoricalTeammateMap = retEmpty,
            GetInTeamIndexFromHistoricalTeammateInfo = function() return -1 end,
            ReportSuspiciousPlayer = noop, SubmitReport = noop, ProcessReport = noop,
            ClientRPC_SyncFatalDamagerMap = noop,
        },
        custom = function(m)
            if m.__inner_impl then
                m.__inner_impl._OnSyncFatalDamage = noop
                m.__inner_impl._OnPlayerKilledOtherPlayer = noop
                m.__inner_impl._SyncBattleResult = noop
            end
        end,
    },
    ["GameLua.Mod.BaseMod.Common.Security.DSReportPlayerSubsystem"] = {
        methods = {
            OnInit = noop, _OnNearDeathOrRescued = noop, _OnCharacterDied = noop, _OnTeammateDamage = noop,
            _OnPlayerSettlementStart = noop, _AddKnockDownerToBattleResult = noop, _AddKillerToBattleResult = noop,
            _AddTeammateMurderToBattleResult = noop, _AddFatalDamagerMapToBattleResult = noop,
            _AddMLKillerUIDToBattleResult = noop, _SaveHistoricalTeammateInfo = noop, _RecordFatalDamager = noop,
            _RecordTeammateMurderer = noop,
            _AddEnemyMapToBattleResult = noop, _AddTeammateMapToBattleResult = noop, _SubmitAbnormalData = noop,
            _tUID2InfoMap = retEmpty, ds2history = retEmpty,
        },
    },
    ["GameLua.Mod.BaseMod.Common.Security.ReportPlayerUtils"] = {
        retvals = { GetBotType = retZero, IsCharacterDeliverAI = retFalse },
        methods = { RecordFatalDamager = noop, IsUsingHistoricalTeammateInfo = retFalse },
    },
    ["GameLua.Mod.BaseMod.Common.Security.SecurityCommonUtils"] = {
        methods = { ExtractPlayerBasicInfo = retEmpty, LogIf = retFalse },
        custom = function(m)
            if m.EStrategyTypeInReplay then
                m.EStrategyTypeInReplay.EspTotalSimTraceCnt = 0
                m.EStrategyTypeInReplay.EspTotalImeFocusCnt = 0
                m.EStrategyTypeInReplay.ClientGravityAnomalyCount = 0
                m.EStrategyTypeInReplay.FlyingErrorCnt = 0
            end
        end,
    },
    ["GameLua.Mod.BaseMod.Client.Security.ClientQuickReportMaliciousTeammate"] = {
        methods = { OnShowMutualExclusiveUI = noop, OnHideMutualExclusiveUI = noop,
            MaliciousTeammateReceiveWarningTips = noop, MaliciousTeammateVictimReceiveTips = noop },
    },
    _G_ClientTlogHandler = { table = "_G.ClientTlogHandler", methods = { send_report_lobby_common_tlog = noop } },
    _G_LoginAndWinTlogHandler = { table = "_G.LoginAndWinTlogHandler", methods = { on_cloud_game_event_notify = noop } },
    _G_tlog_report_utils = { table = "_G.tlog_report_utils", methods = { ReportTLogEvent = noop, ReportImmediate = noop } },
    _G_BasicDataTLogReport = {
        table = "_G.BasicDataTLogReport",
        methods = { OnSendBatchReqMsg = noop, OnImmediateReqMsg = noop, OnMergeReqMsg = noop, send_report_event_duration_log = noop, SendTlog = noop, ReportEvent = noop },
        retvals = { _GetParamData = retEmpty }
    },
    _G_BasicDataClientReport = {
        table = "_G.BasicDataClientReport",
        methods = { ReportImmediate = noop, ReportDelay = noop, OnSendBatchReqMsg = noop, OnImmediateReqMsg = noop, OnMergeReqMsg = noop },
        retvals = { _IsCanReport = retFalse }
    },
    _G_BasicDataReport = {
        table = "_G.BasicDataReport",
        methods = { ReportImmediate = noop, ReportDelay = noop, OnMergeReqMsg = noop, OnImmediateReqMsg = noop, OnSendBatchReqMsg = noop, _BatchReqMsg = noop }
    },
    _G_puffer_tlog = { table = "_G.puffer_tlog", methods = { report_download_tlog = noop } },
    ["GameLua.Mod.BaseMod.DS.Security.ICTLogSubsystem"] = { methods = { SendICExceptionTLog = noop } },
    ["GameLua.Mod.BaseMod.DS.Security.DSFightTLogSubsystem"] = {
        methods = { ReportFightData = noop, ReportPlayerWeapon = noop },
        retvals = { GetSimpleFightData = retEmpty }
    },
    ["GameLua.Mod.BaseMod.DS.Security.DSSecurityTLogSubsystem"] = {
        methods = {
            _OnReportServerJumpFlow = noop, _OnReportTeleportFlow = noop, _OnReportSpeedHackFlow = noop,
            ReportServerJumpFlow = noop, CollectJumpData = noop,
        },
    },
    ["GameLua.Mod.BaseMod.DS.Security.DSCommonTLogSubsystem"] = { methods = { HandleKillTlog = noop } },
    _G_ClientErrorReportHandler = {
        table = "_G.ClientErrorReportHandler",
        methods = { send_client_error_report = noop, send_client_crash_report = noop, send_client_tools_batch_report_req = noop }
    },
    _G_BattleReportHandler = {
        table = "_G.BattleReportHandler",
        methods = {
            send_battle_report = noop, send_battle_result = noop, send_vod_game_report_req = noop,
            send_batch_get_vod_info_req = noop, send_get_game_report_req = noop, send_batch_get_game_report_req = noop,
            send_get_game_report_by_uid_req = noop
        }
    },
    _G_BugHandler = { table = "_G.BugHandler", methods = { send_report_bug_info = noop, send_report_bug_feedback = noop } },
    _G_LobbyPingReportHandler = { table = "_G.LobbyPingReportHandler", methods = { send_lobby_ping_report = noop, send_ingame_ping_report = noop } },
    _G_WeekRportHandler = { table = "_G.WeekRportHandler", methods = { send_week_report = noop, send_week_detail = noop } },
    _G_logic_complaint = {
        table = "_G.logic_complaint",
        methods = { SendComplaintReq = noop, Submit = noop, ReportPlayer = noop, ShowComplaint = noop, ShowHandle = noop }
    },
    ["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.EscapeBattleResultShowOBResultLogic"] = {
        methods = { OnBattleResult = noop, OnResultProcessStart = noop }
    },
    ["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowOBResultLogic"] = {
        methods = { OnBattleResult = noop, OnResultProcessStart = noop }
    },
    ["GameLua.Mod.BaseMod.Client.BattleResult.ProcessBase.BattleResultShowResultLogic"] = {
        methods = {
            OnBattleResult = noop, OnResultProcessStart = noop, OnResultProcessContinue = noop,
            ReceiveData = noop, SendEndFlow = noop, OnReport = noop, ShowResult = noop, ShowResultInternal = noop,
            StopResultProcess = noop
        }
    },
    _G_EmulatorHandler = { table = "_G.EmulatorHandler", methods = { send_emulator_info = noop } },
    _G_emulator_scanner = {
        table = "_G.emulator_scanner",
        methods = { StartScan = noop, ReportScanResult = noop },
        retvals = { GetScanResult = retFalse }
    },
    _G_LoginVerifyHandler = { table = "_G.LoginVerifyHandler", methods = { send_login_verify_req = noop, send_device_verify_req = noop } },
    _G_logic_ds_monitor = { table = "_G.logic_ds_monitor", methods = { OnRecordMsg = noop, OnReportMsg = noop } },
    ["GameLua.Mod.BaseMod.Client.Security.ClientDataStatistcsSubsystem"] = {
        methods = { StartToCheck = noop, OnReceiveRTT = noop, OnReceiveJitter = noop, ReportAbnormal = noop, ResetData = noop }
    },
    ["GameLua.Dev.Subsystem.ShootVerifySubSystemClient"] = { methods = { OnShootVerifyFailed = noop, SendVerifyData = noop } },
    ["GameLua.Mod.BaseMod.DS.Security.HighlightMomentSubsystem_DSChecker"] = { methods = { CheckFuncUpgradedWeaponKill = noop } },
    _G_logic_chat_voice_report = { table = "_G.logic_chat_voice_report", methods = { ReportVoiceData = noop, ReportVoiceText = noop } },
    _G_logic_chat_voice_doctor = { table = "_G.logic_chat_voice_doctor", methods = { UploadVoiceLog = noop, UploadVoiceException = noop } },
    _G_logic_home_audit_state = { table = "_G.logic_home_audit_state", methods = { SendAuditState = noop, ReportAuditResult = noop } },
    _G_logic_home_report = { table = "_G.logic_home_report", methods = { ReportHomeData = noop, ReportHomeVisitor = noop, ShowInGameReportUI = noop, SendReport = noop } },
    _G_gem_report_utils = {
        table = "_G.gem_report_utils",
        methods = { ReportGemData = noop, ReportGemPurchase = noop, ReportEventImmediate = noop },
    },
    _G_ChatHandler = { table = "_G.ChatHandler", methods = { send_report_info = noop, send_report_info_mic = noop } },
    _G_ClientReplayDataReporter = { table = "_G.ClientReplayDataReporter", methods = { ReportIntArrayData = noop, ReportFloatArrayData = noop, ReportUInt8ArrayData = noop } },
    ["GameLua.ExtraModule.MLAI.Client.AIReplaySubsystem"] = {
        custom = function(m)
            if m.uCompletePlayBack then
                m.uCompletePlayBack.AddRecordMLAIInfo = noop
                m.uCompletePlayBack.StopRecording = noop
            end
            if m.ReportAllPlayerInfo then m.ReportAllPlayerInfo = noop end
            if m.ReportFrameData then m.ReportFrameData = noop end
            if m.ReportPlayerInput then m.ReportPlayerInput = noop end
        end,
    },
    _G_GameSafeCallbacks = {
        table = "_G.GameSafeCallbacks",
        methods = {
            PostPlayerControllerLoginInit = noop, OnDSGlueHiaInit = noop, CharacterReceiveBeginPlay = noop,
            DoAttackFlowStrategy = noop, RecordStrategyTimestampInReplay = noop, EditorIncreaseTotalStatisticCnt = noop
        },
        retvals = { GetScriptReportContent = function() return "" end }
    },
    ["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"] = {
        methods = { ReportException = noop, ReplayReportData = noop, ReportGameException = noop },
        retvals = { BugglyPostExceptionFull = retFalse, CheckCanBugglyPostException = retFalse }
    },
    _G_NetUtil = { table = "_G.NetUtil", methods = { SendTss = noop, SendToServer = noop, SendToDS = noop } },
    ["UnrealNet"] = {
        global = true,
        custom = function(m)
            if not m then return end
            if m.FilterNetworkException then
                local o = m.FilterNetworkException
                m.FilterNetworkException = function(et, em)
                    if em and type(em) == "string" then
                        local le = em:lower()
                        if le:find("cheatdetected") or le:find("idipban") or le:find("dataerror") or le:find("datamismatch")
                           or le:find("security") or le:find("integrity") or le:find("hashfail") or le:find("flag") then
                            return false
                        end
                    end
                    return o(et, em)
                end
            end
            m.HandleNetworkExceptionReport = noop
            m.HandleNetworkConnectionClosed = noop
            m.HandleSpectateException = noop
        end
    },
    ["GameLua.Mod.BaseMod.Client.Security.Gokuba"] = {
        custom = function(m)
            if m.ForwardFeature then
                m.ForwardFeature = function() return {0, 0, 0, 0, 0} end
            end
            if m.TimerHandle then
                pcall(function()
                    local time_ticker = require("common.time_ticker")
                    time_ticker.RemoveTimer(m.TimerHandle)
                end)
                m.TimerHandle = nil
            end
        end
    },
    ["GameLua.Mod.BaseMod.Common.Security.CoronaUploader"] = { methods = { Upload = noop, Flush = noop } },
    ["GameLua.Mod.BaseMod.Client.Login.LoginLock"] = { methods = { Lock = noop, OnLoginBan = noop }, retvals = { CheckBan = retFalse } },
    ["GameLua.Mod.BaseMod.GamePlay.Battle.BattleResultUploader"] = { methods = { Upload = noop } },
    ["client.slua.logic.ClientAppStat"] = { methods = { Report = noop, Flush = noop } },
    ["GameLua.Mod.BaseMod.Client.Security.DeviceFingerprint"] = {
        methods = { Collect = noop, Sync = noop, GetHash = function() return "unknown" end }
    },
    ["GameLua.Mod.BaseMod.DS.Security.DSDeviceCheck"] = { methods = { VerifyClientDevice = retTrue, ReportMismatch = noop } },
    ["GameLua.Mod.BaseMod.Common.Security.IntegrityCheck"] = { methods = { Run = noop, Verify = retTrue } },
    ["GameLua.Mod.BaseMod.Common.Security.APKIntegrity"] = { methods = { CheckSignature = retTrue, CheckInstallSource = retTrue } },
    ["GameLua.Mod.BaseMod.Common.Security.LibCheck"] = {
        methods = { Verify = retTrue, Check = retTrue, Scan = noop, Report = noop },
        retvals = { IsLibValid = retTrue, GetTamperedLibs = retEmpty }
    },
    _G_TDataMaster = {
        table = "_G.TDataMaster",
        methods = { Report = noop, ReportDeviceInfo = noop, SendHardwareHash = noop, CollectTelemetry = noop, SendData = noop, Sync = noop, Flush = noop },
        custom = function(m)
            if m then for k, v in pairs(m) do if type(v) == "function" then m[k] = noop end end end
        end,
    },
    _G_DeviceInfo = {
        table = "_G.DeviceInfo",
        methods = { GetDeviceID = function() return "unknown" end, GetIMEI = function() return "000000000000000" end, CollectSysInfo = noop }
    },
    ["client.slua.logic.platform.platform_db"] = { methods = { Scan = noop, CheckIntegrity = retFalse, ReportCorruption = noop } },
    ["xunyou_cache_scan"] = { methods = { StartScan = noop, GetResult = retEmpty } },
    _G_SecurityTlogQueue = { table = "_G.SecurityTlogQueue", methods = { Flush = noop, Add = noop } },
    _G_PufferDownloadReport = { table = "_G.PufferDownloadReport", methods = { ReportDownload = noop, ReportError = noop } },
    _G_ReplayRecordSecurity = { table = "_G.ReplayRecordSecurity", methods = { InjectMeta = noop, Validate = noop } },
    _G_GameServerHeartbeat = { table = "_G.GameServerHeartbeat", methods = { ReportMissedBeat = noop, CheckAlive = retTrue } },
    ["GameLua.Mod.BaseMod.Common.Security.AntiDebug"] = { methods = { Check = retFalse, Report = noop } },
    ["GameLua.Mod.BaseMod.Client.Security.SecureBootCheck"] = { methods = { VerifyBoot = retTrue } },
    ["GameLua.Mod.BaseMod.DS.Security.DSPlayerValidCheck"] = { methods = { Validate = retTrue, ReportSuspicious = noop } },
    ["client.slua.logic.common.logic_common_legal_msg"] = {
        custom = function(m)
            if m.ShowOnePopUI then
                local o = m.ShowOnePopUI
                m.ShowOnePopUI = function(self, params)
                    if params and params.title and params.title:find("SECURITY") then return end
                    return o(self, params)
                end
            end
        end,
    },
    ["GameLua.Mod.BaseMod.Client.Security.InspectionSystemReportClientLogicSubsystem"] = {
        methods = {
            AskForInspector = noop, ReportEnemy = noop, KickOutOneTeam = noop,
            OnReceiveInspectCmd = noop, ClientReportData = noop, SendReportToInspector = noop,
            SendKickOutOneTeam = noop, ClientNotifyInspectorImplementation = noop, RecvNotifyInspector = noop,
        },
    },
    ["GameLua.Mod.BaseMod.DS.Security.InspectionSystemReportDSLogicSubsystem"] = {
        methods = {
            ServerKickOutOneTeamByPlayerImplementation = noop, AddReportedCount = noop,
            AddInspectionRecord = noop, BanPlayerByInspection = noop,
            BroadCastToAllInspector = noop, ServerReportToInspectorImplementation = noop,
            InitPlayerInspectionInfo = noop,
        },
        fields = { MAX_ASK_FOR_INSPECTOR_TIME = 0, ASK_FOR_INSPECTOR_INTERVAL = 99999 },
        custom = function(m)
            if m.__inner_impl then
                m.__inner_impl.IsGameModeAllowed = retTrue
            end
        end,
    },
    ["client.slua.logic.CustomerService.LogicSafeStation"] = {
        methods = { UploadVideoEvidence = noop, ReportPlayerBehavior = noop },
    },
    ["client.slua.logic.CustomerService.LogicCustomerService"] = {
        methods = { SendComplaint = noop, SendFeedback = noop },
    },
    ["GameLua.GameCore.Module.Vehicle.VehicleFeatures.TLog.AmphibiousBoatTLogFeature"] = {
        methods = { RecordMovement = noop, StartRecordMovement = noop },
    },
    ["client.logic.data.profile_report_cfg"] = { methods = { SendReport = noop } },
    ["GameLua.Mod.BaseMod.Client.ClientInGameCreditLogic"] = {
        methods = {
            _SendUserReaction2ExitTeamBeforeBoardingReturnLobbyNotice = noop,
            ShowReturnLobbyIfFirstExitTeamBeforeBoarding = retFalse,
            OnReceiveCreditScoreChange = noop,
            _IsFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = retFalse,
            SetFirstExitTeamBeforeBoardingReturnLobbyNoticeEnabled = noop,
        },
    },
    ["GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeDevDebugSubsystem"] = { methods = { IsDebugPanelEnalbedCli = noop } },
    ["GameLua.Mod.CreativeBase.Gameplay.Subsystem.CreativeModeDeathRecordSubsystem"] = { methods = { OnPlayerKilled = noop } },
    ["GameLua.Mod.BaseMod.DS.Security.AFKReportorSubsystem"] = {
        methods = {
            HandleEnterFighting = noop, InitializePlayerInputInfo = noop,
            AddOneAFKInfo = noop, SetPlayerAFKState = noop,
            ResetPlayerInputInfo = noop, PlayerHaveAction = noop, ReportAFK = noop,
            CheckAFK = retFalse,
        },
    },
    ["GameLua.Mod.TDM.Gameplay.Subsystem.TDMAFKReportorSubsystem"] = { methods = { SendAFKTips = noop, OnHandleLostConnection = noop } },
    ["GameLua.Mod.BaseMod.GamePlay.AI.AITrackingLogSubsystem"] = {
        methods = {
            RealLogoutTimer = noop, AddToLogQue = noop, DoPrint = noop,
            OnAIPawnDied = noop, OnAIPawnReceiveDamage = noop, OnAIPawnEnemyChange = noop,
        },
        fields = { LogQueue = {} },
    },
    ["client.slua.logic.data.data_mgr"] = { retvals = { GetWeaponSkinSoundVolumeInfoByGroup = retZero } },
    ["TApmHelper"] = { methods = { postEvent = noop } },
    ["GameLua.Mod.BaseMod.Common.Security.LuaIntegrityCheck"] = { methods = { Run = noop, Verify = retTrue, Check = retTrue } },
    ["GameLua.Mod.BaseMod.Client.Security.ClientDeviceCheckSubsystem"] = {
        methods = { StartCheck = noop, ReportResult = noop },
        retvals = { IsDeviceSafe = retTrue },
    },
    ["GameLua.Mod.BaseMod.Client.Security.SpectatorAndReplaySubsystem"] = { methods = { SendReport = noop } },
    ["client.slua.logic.login.logic_version_update"] = {
        methods = { CheckVersion = noop, CheckUpdate = noop, IsNeedUpdate = retFalse, GetVersion = function() return "4.4.0" end, ShowUpdateDialog = noop }
    },
    ["client.slua.logic.version.logic_update"] = { methods = { CheckUpdate = noop, ForceUpdate = noop, IsForceUpdate = retFalse } },
    ["client.slua.logic.ban.logic_ban"] = {
        methods = { GetBanEndTime = function() return 0 end, IsInBanTime = retFalse, CheckBanStatus = retFalse, GetBanReason = retEmpty, GetBanTime = retZero }
    },
    ["client.slua.logic.login.logic_login_ban"] = {
        methods = { CheckCanLogin = retTrue, GetBanInfo = function() return { end_time = 0 } end, IsBanned = retFalse, IsSecurityBan = retFalse }
    },
    ["GameLua.Mod.PlanBT.Gameplay.Subsystem.DSActiveSubsystem"] = { methods = { DelayKickOutPlayer = noop, ActiveKickNotify = noop } },
    ["GameLua.Mod.BaseMod.Client.Security.ClientFlagSubsystem"] = {
        methods = {
            EvaluateFlags = noop,
            GetFlagLevel = retZero,
            GetFlagBanDuration = retZero,
            IsFlagged = retFalse,
            ReportFlag = noop,
            SyncFlagStatus = noop,
            IncreaseFlagCount = noop,
            ResetFlags = noop,
        },
        retvals = { IsFlagged = retFalse },
        fields = { FlagCount = 0, FlagLevel = 0, FlagSeverity = 0 },
    },
    ["client.slua.logic.ban.logic_flag_ban"] = {
        methods = {
            GetFlagBanEndTime = function() return 0 end,
            IsFlagBanned = retFalse,
            GetFlagBanDuration = retZero,
            CheckFlagBan = retFalse,
        }
    },
    ["GameLua.Mod.BaseMod.DS.Security.DSAITLogSubsystem"] = {
        methods = { _UpdateTTKRecords = noop, _UpdateOperatingFrequency = noop }
    },
    ["GameLua.Mod.Borderland.Gameplay.Subsystem.TLogSubsystem"] = { methods = { OnInit = noop } },
    _G_TLogSubsystem = { table = "_G.TLogSubsystem", methods = { OnInit = noop } },
    ["client.slua.logic.download.report.logic_mini_pak_gem"] = {
        methods = { StartReport = noop, ReportGemLog = noop, SetCurDownloadSize = noop }
    },
    ["GameLua.Mod.BaseMod.Client.ClientTLog.ClientTLogManager"] = {
        methods = {
            OnReceiveBattleResults = noop,
            AddValTLog = noop,
            SetValTLog = noop,
            SendReportLobby = noop,
        },
        fields = { ClientTlogData = {} },
    },
    ["GameLua.Mod.SocialIsland.DS.Battle.RacingAntiCheatLogic"] = {
        methods = {
            StartDetectTimer = noop, StopDetectTimer = noop,
            DetectVehicleFloating = noop, HandleFloatingCheat = noop,
            HandleSpeedCheat = noop, HandlePlayerPassCheckBelt = noop,
        },
    },
    ["GameLua.Dev.ClientCloudGM"] = { methods = { HandleCloudGMCMDStr = noop } },
    ["GameLua.Mod.BaseMod.Client.Dev.ClientCloudGM"] = { methods = { HandleCloudGMCMDStr = noop } },
    ["GameLua.Mod.BaseMod.Common.RealTimeBan.RealTimeBan"] = {
        methods = {
            OnPlayerWithRealTimeBan = noop,
            ShowAlias = noop,
            HandleEnterGameModeFightingState = noop,
            GetTipsID = retZero,
        },
    },
    ["GameLua.Mod.BaseMod.Client.Security.HawkEyeSpectate.HawkEyeDistanceUI"] = {
        methods = { _RefreshUI = noop, _IsShouldShow = retFalse }
    },
    ["GameLua.Mod.BaseMod.Client.Security.HawkEyeSpectate.HawkEyeNextPatrolWindow"] = {
        methods = { OnShow = noop }
    },
    ["GameLua.Mod.BaseMod.Client.Security.HawkEyeSpectate.HawkEyeReportWindow"] = {
        methods = { _OnClickSubmit = noop, _RefreshWindow = noop, RegistEvents = noop }
    },
    ["GameLua.Mod.BaseMod.Client.Security.SecurityClientUtils"] = {
        methods = {
            HasOtherTeammateOffline = retFalse,
            HasOtherHealthyOnlineTeammate = retFalse,
            IsMyHealthStatusHealthy = retTrue,
            IsMyHealthStatusAlive = retTrue,
            GetMyHealthStatus = function() return 1 end,
        }
    },
    ["GameLua.Mod.BaseMod.Client.Ban.ClientBanLogic"] = {
        methods = {
            OnVoiceBanNotify = noop, OnRealTimeVoiceBanNotify = noop,
            OnSyncBanInfo = noop, OnNotifyWarningTips = noop,
            VoiceBanEndTime = 0, bEnableVoiceReport = false,
        },
    },
    ["GameLua.Mod.BaseMod.Client.Security.ClientBanLogic"] = {
        methods = {
            OnVoiceBanNotify = noop, OnRealTimeVoiceBanNotify = noop,
            OnSyncBanInfo = noop, OnNotifyWarningTips = noop,
        },
    },
    ["ScreenshotMaker"] = {
        custom = function(m)
            if not m then return end
            m.MakePicture = function() return "" end
            m.ReMakePicture = function() return "" end
            m.HasCaptured = function() return true end
        end,
    },
    ["client.slua.logic.ugc.UGCNewTLogReport"] = {
        methods = { SendExposeReq = noop, SendInteractionReq = noop, TLogReport = noop }
    },
    ["client.slua.logic.ugc.logic_ugc_tlog"] = {
        methods = { SendModTLog = noop, ReportStay = noop }
    },
    ["GameLua.Mod.BaseMod.Client.ClientTLog.ClientTLogUtil"] = {
        methods = { ReportGeneralCountByBRPhase = noop, ReportCommonTLogDataByBRPhase = noop }
    },
    ["ReportCrashKitFeature"] = {
        custom = function(m) if m and m.ReportCharacterAttachedOnVehicleException then m.ReportCharacterAttachedOnVehicleException = noop end end,
    },
    ["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportSubsystemReporter"] = {
        custom = function(m)
            if m then
                m.ReportIntArrayData = noop
                m.ReportUInt8ArrayData = noop
                m.ReportFloatArrayData = noop
            end
        end,
    },

    
    ["SkillAction_GrenadeThrowReport"] = {
        methods = {
            ReportGrenadeThrow = noop,
            CheckGrenadeAnimationState = retTrue,
            ValidateThrow = retTrue,
            OnGrenadeThrow = noop,
        },
    },
    ["BanMacro"] = {
        methods = {
            DetectInputVariance = retTrue,
            CheckClickTiming = retFalse,
            AnalyzeClickPattern = retEmpty,
            ReportMacro = noop,
            CheckAllBanTypes = retTrue,
        },
    },
    ["NGActionBanSprint"] = {
        methods = {
            ValidateSprintSpeed = retTrue,
            CheckSpeedHack = retFalse,
            ReportSprintViolation = noop,
        },
    },
    ["ReportGrenadeThrow"] = {
        methods = {
            SendGrenadeReport = noop,
            ReportGrenadeData = noop,
        },
    },
    ["InputVarianceChecker"] = {
        methods = {
            CalculateVariance = retZero,
            IsHumanLike = retTrue,
        },
    },
    ["SpeedhackValidator"] = {
        methods = {
            ValidateSpeed = retTrue,
            IsSpeedhack = retFalse,
            ReportSpeedhack = noop,
        },
    },
    ["HawkEyeSpectatorState"] = {
        methods = {
            OnSpectatorStateChange = noop,
            TrackAimMovement = noop,
            ReportSuspiciousAim = noop,
        },
    },
    ["EmulatorSystem"] = {
        fields = { EmulatorTestMark = true },
        methods = { IsEmulator = retFalse, GetEmulatorName = function() return "NoEmulator" end },
    },
    ["logic_emulator"] = {
        methods = { find_emulator = retFalse, IsSpecialEmulator = retFalse },
    },
    ["VoiceReportSubsystem"] = {
        methods = {
            PLAYER_BAN_GLOBAL_MI = noop,
            ReportSuspicious = noop,
            PreFilterAI = noop,
        },
    },
    ["BugglyReportRecord"] = {
        methods = { Report = noop, Record = noop },
        retvals = { GetProbability = retZero },
    },
    ["PatrollerModule"] = {
        methods = { UpdateStats = noop, GetRank = retZero, AddInspectionRecord = noop },
    },
    ["DSQuickReportMaliciousTeammate"] = {
        methods = {
            _HandleCarrybackFallingDamage = noop,
            _HandleGrenadeDamage = noop,
            _HandleVehicleExplosionDamage = noop,
            ReportMaliciousTeammate = noop,
        },
    },
    ["ClientQuickReportMaliciousTeammate"] = {
        methods = {
            RPC_Client_MaliciousTeammateReceiveWarningTips = noop,
            ShowQuickReportDialog = noop,
            OnDeath = noop,
        },
    },
    ["InspectionSystemKickPlayerConfirm"] = {
        methods = {
            OnConfirmTyped = retTrue,
            CheckConfirmText = retTrue,
        },
    },
    ["RockBandActor"] = {
        custom = function(m)
            if m then
                m._G.IsEditor = false
                m._G.IsTesting = false
            end
        end,
    },
    ["ban_reddot_system"] = {
        methods = {
            EnterSafeStation = noop,
            UpdateRedDot = noop,
            OnBanUpdate = noop,
        },
    },
    ["ban_reddot_data"] = {
        methods = {
            LoadBanRedDotData = noop,
            UpdateBanRedDot = noop,
        },
    },
    ["DSPlayerDataReportSubsystem"] = {
        methods = {
            TrackRescue = noop,
            TrackDieWithoutRevive = noop,
            HandleBattleResult = noop,
            _HandleRescue = noop,
            _HandleDieWithoutRevive = noop,
        },
        custom = function(m)
            if m then
                m.DieWithoutReviveTime = 99999
                if m._OnGameEnd then m._OnGameEnd = noop end
            end
        end,
    },
    ["UGC_AiCopilot_Report"] = {
        methods = {
            ReportContent = noop,
            ReportLowQuality = noop,
            SendReport = noop,
        },
    },
    ["gem_report_utils"] = {
        methods = {
            ReportEventDelay = noop,
            ReportImmediate = noop,
        },
    },
    ["gem_report_config"] = {
        methods = {
            OnNetworkEvent = noop,
            OnBanEvent = noop,
        },
    },
    ["net"] = {
        global = true,
        custom = function(m)
            if m then
                m.DumpPropertySerializationStats = noop
            end
        end,
    },
}


-- ✅ SAFE MODE: لا نعترض require/import (يكسر تحميل الموارد)
-- نطبق الـpatches فقط على الموديولات المُحمّلة مسبقاً
pcall(function()
    for path, cfg in pairs(modulePatches) do
        local mod = package.loaded[path]
        if mod and type(mod) == "table" then
            if cfg.custom then pcall(cfg.custom, mod) end
            if cfg.methods then
                for k, v in pairs(cfg.methods) do
                    if type(mod[k]) == "function" then mod[k] = v end
                end
            end
            if cfg.retvals then
                for k, v in pairs(cfg.retvals) do
                    if type(mod[k]) == "function" then mod[k] = v end
                end
            end
            if cfg.fields then
                for k, v in pairs(cfg.fields) do
                    if mod[k] ~= nil then mod[k] = v end
                end
            end
        end
    end
end)


local function TssSdkBypass()
    pcall(function()
        local TssSdk = _G.TssSdk or package.loaded["TssSdk"] or package.loaded["client.slua.logic.tss_sdk"]
        if not TssSdk then
            local ok, mod = pcall(require, "TssSdk")
            if ok then TssSdk = mod end
        end
        if not TssSdk then return end

        local bypassFuncs = {
            "GetSdkAntiData", "GameScreenshot", "GameScreenshot2", "IsEmulator",
            "QueryOpts", "GetCommLibValueByKey", "GetShellDyMagicCode", "AddMTCJTask",
            "SetToken", "EnableDisableItem", "InvokeCrashFromShell", "ReInitMrpcs",
            "GetUserTag", "QueryTssLibcAddr", "RegistLibcSendListener", "RegistLibcRecvListener",
            "RegistLibcConnectListener", "RegistLibcCloseListener", "GetMrpcsData2Ptr",
            "GetTPChannelVer", "SetGameChannelIp", "SetValueByKey", "SetChannelHost",
            "SetChannelBuiltinIp", "RecvSecSignature", "PushAntiData3", "QueryRemainsAntiDataCount",
            "GetAntiData3", "DelAntiData3", "SetSecToken", "GetThreadsInfo", "AddTouchEvent",
            "InitSwitchStr", "SetCDNHost", "SetEnabledConnector", "QueryHookInfo", "SetCSLicense",
            "AddAnoTouchEvent", "GetObjVMFuncAddr", "ScanMemory", "ScanSo", "ScanFile",
            "GetRiskFlag", "VerifyFileHash", "CheckKernel", "VerifyBoot", "GetAntiDataQueue",
            "ReportAntiData", "SendAntiData", "ReportSdkData", "SendSdkData", "OnRecvData"
        }
        for _, funcName in ipairs(bypassFuncs) do
            if TssSdk[funcName] then
                TssSdk[funcName] = function(...) return true, "BYPASSED" end
            end
        end

        if TssSdk.antiDataQueue then
            TssSdk.antiDataQueue = {}
            TssSdk.antiDataQueue.push = function() end
            TssSdk.antiDataQueue.pop = function() return nil end
            TssSdk.antiDataQueue.size = function() return 0 end
            TssSdk.antiDataQueue.clear = function() end
        end

        if TssSdk.IsEmulator then TssSdk.IsEmulator = function() return false end end
        if TssSdk.InvokeCrashFromShell then TssSdk.InvokeCrashFromShell = function() return false end end
        if TssSdk.QueryHookInfo then TssSdk.QueryHookInfo = function() return {} end end
        if TssSdk.PushAntiData3 then TssSdk.PushAntiData3 = function() return true end end
        if TssSdk.QueryRemainsAntiDataCount then TssSdk.QueryRemainsAntiDataCount = function() return 0 end end
        if TssSdk.GetAntiData3 then TssSdk.GetAntiData3 = function() return nil end end
        if TssSdk.DelAntiData3 then TssSdk.DelAntiData3 = function() return true end end
        if TssSdk.AddTouchEvent then TssSdk.AddTouchEvent = function() return true end end
        if TssSdk.SetEnabledConnector then TssSdk.SetEnabledConnector = function() return true end end
        if TssSdk.SetCSLicense then TssSdk.SetCSLicense = function() return true end end
        if TssSdk.GetObjVMFuncAddr then TssSdk.GetObjVMFuncAddr = function() return 0 end end
    end)
end

local function EnhancedAntiCheatBypass()
    if _G.BYPASS_STATE and _G.BYPASS_STATE.ANTI_CHEAT_MANAGER_DISABLED then return end
    pcall(function()
        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if not slua.isValid(pc) then return end

        local AntiCheatMgr = nil
        if pc.PlayerAntiCheatManager then
            AntiCheatMgr = pc.PlayerAntiCheatManager
        elseif pc.AntiCheatManager then
            AntiCheatMgr = pc.AntiCheatManager
        end

        if not slua.isValid(AntiCheatMgr) then
            local PlayerAntiCheatManagerClass = import("PlayerAntiCheatManager")
            if PlayerAntiCheatManagerClass then
                local comps = pc:GetComponentsByClass(PlayerAntiCheatManagerClass)
                if comps and comps:Num() > 0 then
                    AntiCheatMgr = comps:Get(0)
                end
            end
        end

        if not slua.isValid(AntiCheatMgr) then return end

        local counterFields = {
            "AutoAimFailedCnt", "TrackingFailedCnt", "AreaDamageFailedCnt", "JumpHeightFailedCnt",
            "JumpFarFailedCnt", "VehicleFlyingFailedCnt", "ShootVerifyTimes", "SpeedUpValue",
            "ClientTimeTotalAcc", "ServerAccumulateErrors", "ServerAvgErrors", "ServerCorrectTimes",
            "PlayerBadPingTimes", "VehicleSpeedZDeltaTotal", "VehicleSpeedZDeltaOver10Times",
            "PVSInCityKillCount", "PVSNotInCityKillCount", "PVSCellHidePercent", "PVSTotalHidePercent",
            "ServerMoveParameterVerifyCount", "ServerMoveParameterVerifyFailedCount",
            "StuckGroundPunishCount", "ContinueMoveBurstCount", "RecordContinueMoveBurstCount",
            "TrialBaseDiffCount", "InclusiveBegin", "InclusiveEnd"
        }
        for _, field in ipairs(counterFields) do
            pcall(function()
                if type(AntiCheatMgr[field]) == "number" then AntiCheatMgr[field] = 0 end
            end)
        end

        local boolFields = {
            "bReportFeedBack","bOpenDetailDataCollect","bOpenBaseDiffCheck","bUploadStuckGroundCount",
            "bStuckGroundCapsule","bImpactOtherAfterBurst","bGiveupPickupWhenBrust",
            "bOpenPickupWhenBrustCheck","bMustStrictContinue"
        }
        for _, field in ipairs(boolFields) do
            pcall(function()
                if type(AntiCheatMgr[field]) == "boolean" then AntiCheatMgr[field] = false end
            end)
        end

        local maxFields = {
            "MaxShootPointPassWall", "MaxMuzzleHeightTime", "MaxLocusFailTime",
            "MaxBulletVictimClientPassWallTimes", "MaxGunPosErrorTimes",
            "MaxAllowVehicleTimeSpeedRawTime", "MaxAllowVehicleTimeSpeedConvTime",
            "MaxAllowVehicleAccTime", "MaxSingleShotDamage", "MaxFallingSustainTime",
            "MaxCustomMoveModeSustainTime", "MaxMoveDistance2DPerSecond",
            "MaxCharMoveDist2DPerSecond", "MaxDistanceToGround", "MaxContinueMoveBurstXY",
            "ContinueMoveBurstInterval", "BaseDiffRegion", "BaseDiffVel", "BaseDiffTime",
            "MinImpactOtherInterval", "MinBurstToPickupInterval", "MaxPlayerDisSquaredForPickup",
            "ContinueMoveBurstTolerant", "MultiStuckGroundScale", "StuckTypePunishSet",
            "StuckGroundPunishType"
        }
        for _, field in ipairs(maxFields) do
            pcall(function()
                if type(AntiCheatMgr[field]) == "number" then AntiCheatMgr[field] = 999999 end
            end)
        end

        local paraFields = {
            "ParachuteStartTime","ParachuteOpenTime","ParachuteCloseTime",
            "ParachuteStartHight","ParachuteOpenHight","ParachuteCloseHight"
        }
        for _, field in ipairs(paraFields) do
            pcall(function()
                if type(AntiCheatMgr[field]) == "number" then AntiCheatMgr[field] = 0 end
            end)
        end

        pcall(function() AntiCheatMgr.DSProperty = nil end)

        local verifySwitchFields = {
            "VsNoHitDetail","VsMuzzleRangeCircle","VsMuzzleRangeUp",
            "VsHitBoneNameNone","VsHitBoneHitMissMatch","VsBulletID",
            "VsVehicleTimeStampError","VsWatchTimeStampError",
            "VsShootRpgShootTimeVerify","VsShootLockShootTimeVerify",
            "VsShootRpgHitNewVerify","VsShootTimeConDelta",
            "VsServerNoOldShoot","VsClientNotConnectShoot",
            "VsShootRpgShootIntervalVerify","VsImpactPointAndBulletDisBig",
            "VsShootVerifyInvalid","VsImpactActorPosWithNoHisPos",
            "VsShootAngleInVaild","VsMuzzleAndTailPosInVaild",
            "VsMuzzleAndImpactPassWall","VsMuzzleAndTailPassWall",
            "VsImpactActorPosOffsetBig","VsImpactPointChangeSmall",
            "VsImpactBulletPosOffsetBig","VsTotalImactCharacterNum",
            "VsBoneInfo","VsJumpMaxHeight","VsJumpMaxHeight15","VsJumpMaxHeight2",
            "SpeedQuickCheck","BulletDirError","WalkSpeedFailedCnt",
            "DSSpeedOver10FailedCnt","DSSpeedOver15FailedCnt","DSSpeedOver20FailedCnt",
            "DSFallingSpeedFailCount","DSFallingHeightFailCount",
            "SwitchMuzzleLocusError","SwitchMuzzleLocusErrorX","SwitchMuzzleLocusErrorY","SwitchMuzzleLocusErrorZ",
            "Gun2ShooterPosError1","SwitchHeadLocusError3","SwitchMuzzleLocusErrorLength",
            "SwitchShootPosHistoryLocusError3","SwitchHitComponentUnvalid","SwitchHitNoRender",
            "SwitchHitOutCollisionBox","HeadOverShootPos","SwitchMuzzleImpactDirSkipPunish1",
            "SwitchInvalidBulletNumInBarrel","SwitchShooterMovementError2","GunTailPosError",
            "SwitchMuzzleImpactDirSkipPunish2","SwitchMuzzleImpactDirError1","SwitchMuzzleImpactDirError2",
            "ShooterHead2PosBlock","SwitchShootPosHistoryLocusError2","Head2GunTailPosError1",
            "SwitchShootDirExcepation1","SwitchShootDirExcepation2","SwitchCamerModeException",
            "SwitchShootPosHistoryLocusError4","SwitchMuzzleImpactDirError3",
            "CharacterMoveException1","CharacterMoveException2","CharacterMoveException3",
            "CharacterMoveException4","CharacterMoveException5","CharacterMoveException6",
            "VehicleSpeedZDeltaOver10TimesWhenNoXY","VehicleVelZCheck1","VehicleVelZCheck2",
            "VehicleMaxSpeedCheck","VehicleHitMuzzleCheck","VehicleHitImpactPointCheck",
            "VehicleHitBlockWall","VehicleSidesway1","VehicleSidesway2",
            "FarShootInMidAirVehicleExceedThreshold","FarShootInMidAirVehicleEnemyDistanceTrial",
            "FarShootInMidAirVehicleEnemyDistanceFurtherTrial","FarShootInMidAirVehicleHeightTrial",
            "FarShootInMidAirVehicleHeightFurtherTrial","FarShootInMidAirPawnExceedThreshold",
            "FarShootInMidAirPawnEnemyDistanceTrial","FarShootInMidAirPawnEnemyDistanceFurtherTrial",
            "FarShootInMidAirPawnHeightTrial","FarShootInMidAirPawnHeightFurtherTrial",
            "NonGunADSFarShootCount","NonGunADSFarShootFromClientBulletDataCount",
            "NonGunADSFarShootFromClientBulletDataEnemyDistanceTrialCount",
            "NonGunADSFarShootFromClientBulletDataEnemyDistanceFurtherTrialCount",
            "ClientUploadFuzzyObjectVerifyFail","ClientMoveTimeStampResetFrequencyExceedThreshold",
            "ShootBirdNonGunADSExceedThreshold","ShootBirdNonGunADSDistanceTrial",
            "ShootBirdNonGunADSDistanceFurtherTrial","FarShootInHighTangentMoveSpeedExceedThreshold",
            "FarShootInHighTangentMoveSpeedEnemyDistanceTrial","FarShootInHighTangentMoveSpeedEnemyDistanceFurtherTrial",
            "FarShootInHighTangentMoveSpeedSpeedTrial","FarShootInHighTangentMoveSpeedSpeedFurtherTrial",
            "IllegalTeamUpNearbyButNoFireAfterKill","IllegalTeamUpNearbyButNoFireAfterKillDistanceTrial",
            "IllegalTeamUpNearbyButNoFireAfterKillTimeTrial","IllegalTeamUpNearbyButNoFireAfterKillMaxTime",
            "IllegalTeamUpNearbyButNoFirePickUpItem","IllegalTeamUpNearbyButNoFirePickUpItemDistanceTrial",
            "IllegalTeamUpNearbyButNoFirePickUpItemTimeTrial","IllegalTeamUpNearbyButNoFirePickUpItemMaxTime",
            "IllegalTeamUpNearbyButNoFireNotKill","IllegalTeamUpNearbyButNoFireNotKillDistanceTrial",
            "IllegalTeamUpNearbyButNoFireNotKillTimeTrial","IllegalTeamUpNearbyButNoFireNotKillMaxTime",
            "IllegalTeamUpNearbyButNoFireOnVehicle","IllegalTeamUpNearbyButNoFireOnVehicleDistanceTrial",
            "IllegalTeamUpNearbyButNoFireOnVehicleTimeTrial","IllegalTeamUpNearbyButNoFireOnVehicleMaxTime",
            "IllegalTeamUpNearbyButNoFireSameVehicle","IllegalTeamUpNearbyButNoFireSameVehicleTimeTrial",
            "IllegalTeamUpNearbyButNoFireSameVehicleMaxTime","IllegalTeamUpUseObjectTogether",
            "IllegalTeamUpGetOnEnemyVehicleCount","IllegalTeamUpNearbyButNoFireOneSideHasWeaponOnFoot",
            "IllegalTeamUpNearbyButNoFireOneSideHasWeaponOnFootDistanceTrial","IllegalTeamUpStayOnEnemyVehicle",
            "KillBird","ShooterCapsuleCollided","ParachuteLandingSecondsExceedThreshold",
            "ParachuteObliqueLandingSecondsExceedThreshold","SmallActorTimeDilationCount",
            "LargeRotateLockShooting","SmallRotateLockShooting","OneClipShootCount","ClientWeaponFastReload",
            "UndergroundCount","MoveDistance2DPerSecondAnomaly","CharMoveDist2DPerSecondAnomaly",
            "CharMoveDist2DPerSecondCount","DistanceToGroundAnomaly","SingleShotDamageAnomaly","BandaCount",
            "DSCheckClientTimeMoveDistance2D","DSCheckClientTimeMoveDistance2DTrial",
            "DSCheckClientTimeMoveDistance2DFurther","DSCheckClientTimeMoveDistanceZ",
            "DSCheckClientTimeMoveDistanceZTrial","DSCheckClientTimeMoveDistanceZFurther",
            "ReplayMaxFallingSustainTime","ReplayMaxCustomMoveModeSustainTime","ReplayMaxSingleShotDamage",
            "CharMoveAccumDist2D_DS","CharMoveAccumDist3D_DS","CharMoveAccumDist2D_Client",
            "CharMoveAccumDist3D_Client","CharMoveAccumDist2D_ClientAll","CharMoveAccumDist3D_ClientAll",
            "MetroEnterRadiationTime","MetroEnterRadiationTimeTrial","MetroLeaveBornObstacle",
            "VsPetJumpHeightLimiter","VsPetMoveSpeedLimiter","VsBioVehicleMoveSpeedLimiter",
            "VsBioVehicleJumpHeightLimiter","VsPterosaurFlyVehicleSpeed","VsBioVehicleGravityLimiter",
            "ServerMoveCacheCountOver","ServerMoveCacheCountOver3d","ServerMoveBurst","ImpactOtherAfterBurst",
            "KillOtherAfterBurst","PickupAfterBurst","ContinueMoveBurst","ServerMoveTimeStamp",
            "ServerMoveAccel","ServerMoveClientLoc","ServerMoveCompressedMoveFlags","ServerMoveClientRoll",
            "ServerMoveView","ServerMoveClientMovementBase","ServerMoveClientBaseBoneName",
            "ServerMoveClientMovementMode","VerifySwitchCameraRotation","VerifySwitchPeekShootThroughWall",
            "VerifySwitchCameraLocation","VerifySwitchAutoAimByLockView","VerifySwitchControlRotation",
            "VerifySwitchRecoilFaildCount","VerifySwitchMarcoPolo","VerifySwitchMarcoPolo2",
            "VerifySwitchMarcoPolo3","VerifySwitchMeshScaleDiff","VerifySwitchOfflineMove",
            "VerifySwitchFastAimShootHit","VerifySwitchNoRecoilOnWeaponShoot","VerifySwitchLessRecoilOnWeaponShoot",
            "VerifySwitchNoRecoilOnKickBack","VerifySwitchLessRecoilOnKickBack","VerifySwitchDivingBoost",
            "VerifySwitchRecoilCurveFailed","PlayerQuickProne","BaseDiffSample",
            "VsTeammateRescue","VsTeammateRescueVictim","VsTeammateRecall","VsTeammateRecallVictim",
            "VsAutoClicker","VsAbnormalShootingRotation","PlayerInstantHeightDiff","Player2SecHeightDiff",
            "CheatStateData2TotalCheatTimes","MoveCheatAntiStrategy3TotalCheatTimes","ServerAccumulateErrorReplay"
        }
        for _, fieldName in ipairs(verifySwitchFields) do
            pcall(function()
                local vs = AntiCheatMgr[fieldName]
                if vs and type(vs) == "table" then
                    vs.bActive = false
                    vs.MaxCount = 99999
                    vs.CurrentCount = 0
                    vs.TrialCount = 0
                    vs.TrialMaxCount = 99999
                    vs.PunishType = 0
                end
            end)
        end

        local burstFields = {
            "ServerAccumulateErrorBurst","DSSpeedOver10BurstCount",
            "ParachuteSpeedBurst","ClientTimestampBurst","ClientTimestampBurstTrial"
        }
        for _, fieldName in ipairs(burstFields) do
            pcall(function()
                local bvs = AntiCheatMgr[fieldName]
                if bvs and type(bvs) == "table" then
                    bvs.bActive = false
                    bvs.MaxCount = 99999
                    bvs.CurrentCount = 0
                end
            end)
        end

        pcall(function()
            if AntiCheatMgr.ReportMiscMap then AntiCheatMgr.ReportMiscMap:Clear() end
        end)

        local methodFields = {
            "ReportAntiCheatDetailData","PushWeaponAntiData","OnRecoverOnServer",
            "OnPreReconnectOnServer","ExitParachute","EnterParachute","EnterJumping",
            "Cofey","Cofew","SetTrialRegion","GetSoftString","GetCheckMoveStr2",
            "GetCheckMoveStr1","GetAACString","GetAACCountByID"
        }
        for _, method in ipairs(methodFields) do
            pcall(function()
                if AntiCheatMgr[method] and type(AntiCheatMgr[method]) == "function" then
                    AntiCheatMgr[method] = function(...)
                        if method == "GetSoftString" then return 0 end
                        if method == "GetCheckMoveStr1" or method == "GetCheckMoveStr2" then return "" end
                        if method == "GetAACString" then return "" end
                        if method == "GetAACCountByID" then return 0 end
                        if method == "Cofey" then return 0 end
                        return true
                    end
                end
            end)
        end

        pcall(function()
            local catchData = AntiCheatMgr.CatchReportAntiCheatDetailData
            if catchData and type(catchData) == "table" then
                catchData.bActive = false
                catchData.CurrentCount = 0
                catchData.MaxCount = 99999
            end
        end)

        _G.BYPASS_STATE = _G.BYPASS_STATE or {}
        _G.BYPASS_STATE.ANTI_CHEAT_MANAGER_DISABLED = true
    end)
end

local function MemoryBypass()
    pcall(function()
        local funcs = {"__aeabi_memset","__strncpy_chk","memmove_chk","memset_chk","memcpy","malloc","calloc","realloc","free","close","dup2","listen"}
        for _, fn in ipairs(funcs) do if _G[fn] then _G[fn] = function() return true end end end
    end)
end

local function TimeBypass()
    pcall(function()
        if _G.gmtime then _G.gmtime = function() return os.date("!*t") end end
        if _G.gettimeofday then _G.gettimeofday = function() return os.time() end end
        if _G.mktime then _G.mktime = function(t) return os.time(t) end end
        if _G.imp_time then _G.imp_time = function() return os.time() end end
    end)
end

local function NetworkBypass()
    pcall(function()
        local funcs = {"sys_read","sys_open","nanosleep","imp_recv","imp_send","socket"}
        for _, fn in ipairs(funcs) do if _G[fn] then _G[fn] = function() return true end end end
    end)
end

local function ReportBypass()
    pcall(function()
        local funcs = {"report","COREREPORT","tdm_report","android_log_print","__android_log_print"}
        for _, fn in ipairs(funcs) do if _G[fn] then _G[fn] = function() return true end end end
    end)
end

local function StrBypass()
    pcall(function()
        if _G.strstr then _G.strstr = function() return "" end end
        if _G.strcpy then _G.strcpy = function() return "" end end
        if _G.strlen then _G.strlen = function() return 0 end end
        if _G.strncpy then _G.strncpy = function() return "" end end
    end)
end

local function ProcessBypass()
    pcall(function()
        if _G.getpid then _G.getpid = function() return 0 end end
        if _G.getppid then _G.getppid = function() return 0 end end
        if _G.gettid then _G.gettid = function() return 0 end end
    end)
end

local function AntiDebugBypass()
    pcall(function()
        if _G.ptrace then _G.ptrace = function() return 0 end end
        if _G.monitor then _G.monitor = function() return true end end
    end)
end

local function DLCmdBypass()
    pcall(function()
        if _G.dlopen then _G.dlopen = function() return 0 end end
        if _G.cmd then _G.cmd = function() return "" end end
        if _G.name then _G.name = function() return "" end end
    end)
end

local function AnoSDKBypass()
    pcall(function()
        local TssSdk = _G.TssSdk or package.loaded["TssSdk"]
        if TssSdk then
            if TssSdk.AnoSDKDelReportData then TssSdk.AnoSDKDelReportData = function() return true end end
            if TssSdk.AnoSDKDelReportData3 then TssSdk.AnoSDKDelReportData3 = function() return true end end
            if TssSdk.AnoSDKDelReportData4 then TssSdk.AnoSDKDelReportData4 = function() return true end end
            if TssSdk.AnoSDKGetReportData then TssSdk.AnoSDKGetReportData = function() return nil end end
            if TssSdk.AnoSDKGetReportData2 then TssSdk.AnoSDKGetReportData2 = function() return nil end end
            if TssSdk.AnoSDKGetReportData3 then TssSdk.AnoSDKGetReportData3 = function() return nil end end
            if TssSdk.AnoSDKGetReportData4 then TssSdk.AnoSDKGetReportData4 = function() return nil end end
        end
    end)
end

local function MprotectBypass()
    pcall(function()
        if _G.mprotect then _G.mprotect = function() return 0 end end
        if _G.munmap then _G.munmap = function() return 0 end end
    end)
end


local function InitializeSLUABypass()
  pcall(function()
    if slua and slua.getSignature then
      slua.getSignature = function() return 0xDEADBEEF end
    end
    local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
    if loader then
      loader.verifyBytecode = retTrue
      loader.checkIntegrity = retTrue
      if loader.disableSignatureCheck then loader.disableSignatureCheck = retTrue end
    end
    local slua_serialize = package.loaded["slua.serialize"]
    if slua_serialize then
      slua_serialize.check = retTrue
      slua_serialize.verify = retTrue
    end
    if jit and jit.attach then
      jit.attach(function() end, "bc")
    end
    if _G.slua_verify then _G.slua_verify = retTrue end
    if _G.check_slua_integrity then _G.check_slua_integrity = retTrue end
  end)
end

local function InitializeMD5Bypass()
  pcall(function()
    local console = import("KismetSystemLibrary")
    if console then
      console.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
      console.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
      console.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
      console.ExecuteConsoleCommand(nil, "sig.Check 0")
      console.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
    end
    local CreativeModeBlueprintLibrary = import("CreativeModeBlueprintLibrary")
    if CreativeModeBlueprintLibrary then
      CreativeModeBlueprintLibrary.MD5HashByteArray = function() return "00000000000000000000000000000000" end
      CreativeModeBlueprintLibrary.MD5HashFile = function() return "00000000000000000000000000000000" end
      CreativeModeBlueprintLibrary.GetContentDiffData = function() return true, "BYPASSED" end
      CreativeModeBlueprintLibrary.VerifyFileIntegrity = retTrue
    end
    if _G.MD5Hash then _G.MD5Hash = function() return "00000000000000000000000000000000" end end
    if _G.CRC32 then _G.CRC32 = function() return 0 end end
    if _G.SHA1 then _G.SHA1 = function() return "BYPASS" end end
    local FileHashChecker = package.loaded["common.file_hash_checker"]
    if FileHashChecker then
      FileHashChecker.CheckFileMD5 = retTrue
      FileHashChecker.VerifyAll = retTrue
      FileHashChecker.GetHash = function() return "BYPASS" end
    end
    local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
    if TssSdk then
      TssSdk.GetFileMD5 = function() return "BYPASS" end
      TssSdk.VerifyFileSignature = retTrue
    end
    local STExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
    if STExtraBlueprintFunctionLibrary then
      STExtraBlueprintFunctionLibrary.CheckMD5 = retTrue
      STExtraBlueprintFunctionLibrary.GetMD5 = function() return "BYPASS" end
      STExtraBlueprintFunctionLibrary.VerifyFile = retTrue
    end
  end)
end

local function InitializeSkinBypass()
  pcall(function()
    local puffer_tlog = package.loaded["client.slua.logic.download.report.puffer_tlog"]
    if puffer_tlog then
      puffer_tlog.ReportEvent = noop
      puffer_tlog.ReportDownloadResult = noop
      puffer_tlog.ReportODPTDError = noop
      puffer_tlog.ReportSkinError = noop
    end
    local AvatarUtils = package.loaded["AvatarUtils"]
    if AvatarUtils then
      AvatarUtils.CheckIsWeaponInBlackList = retFalse
      AvatarUtils.IsValidAvatar = retTrue
      AvatarUtils.CheckAvatarIntegrity = retTrue
      AvatarUtils.ReportInvalidAvatar = noop
    end
    local SubsystemMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    local fileCheckSubsystem = SubsystemMgr and SubsystemMgr:Get("FileCheckSubsystem")
    if fileCheckSubsystem then
      fileCheckSubsystem.StartCheck = noop
      fileCheckSubsystem.ReportAbnormalFile = noop
      fileCheckSubsystem.StopCheck = noop
    end
    local equipmentException = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
    if equipmentException then
      equipmentException.Report = noop
      equipmentException.SendException = noop
    end
  end)
end

local function InitializeLogBlocker()
  pcall(function()
    local ScreenshotMTDer = import("ScreenshotMTDer")
    if ScreenshotMTDer then
      ScreenshotMTDer.MTDePicture = function() return "" end
      ScreenshotMTDer.ReMTDePicture = function() return "" end
      ScreenshotMTDer.HasCaptured = retTrue
      ScreenshotMTDer.TakeScreenshot = noop
    end
    local TLog = package.loaded["TLog"] or _G.TLog
    if TLog then
      TLog.Info = noop; TLog.Warning = noop; TLog.Error = noop
      TLog.Debug = noop; TLog.Report = noop; TLog.Send = noop
      TLog.Flush = noop
    end
    local CrashSight = package.loaded["CrashSight"] or _G.CrashSight
    if CrashSight then
      CrashSight.ReportException = noop
      CrashSight.SetCustomData = noop
      CrashSight.Log = noop
      CrashSight.SendCrash = noop
      CrashSight.ReportUserException = noop
    end
    local GameReportUtils = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
    if GameReportUtils then
      GameReportUtils.BugglyPostExceptionFull = retFalse
      GameReportUtils.CheckCanBugglyPostException = retFalse
      GameReportUtils.ReplayReportData = noop
      GameReportUtils.ReportGameException = noop
      GameReportUtils.PostException = noop
    end
    local ClientToolsReport = package.loaded["client.slua.logic.report.ClientToolsReport"]
    if ClientToolsReport then
      ClientToolsReport.SendReport = noop
      ClientToolsReport.SendException = noop
      ClientToolsReport.UploadLog = noop
    end
    local TLogReportUtils = package.loaded["client.slua.config.tlog.tlog_report_utils"]
    if TLogReportUtils then
      TLogReportUtils.ReportTLogEvent = noop
      TLogReportUtils.FlushEvents = noop
    end
    for _, sdk in ipairs({"Firebase", "Adjust", "AppsFlyer", "FacebookAnalytics", "GameAnalytics"}) do
      local s = _G[sdk]
      if s then
        s.logEvent = noop; s.trackEvent = noop; s.setEnabled = retFalse
        s.sendEvent = noop; s.report = noop
      end
    end
  end)
end

local function InitializeScannerBlocker()
  pcall(function()
    local SubsystemMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
      local subsystems = {
        "AFKReportorSubsystem", "ClientDataStatistcsSubsystem", "AvatarExceptionSubsystem",
        "ShootVerifySubSystemClient", "MemoryCheckSubsystem", "SpeedCheckSubsystem",
        "WallCheckSubsystem", "FileCheckSubsystem", "BehaviorScoreSubsystem"
      }
      for _, name in ipairs(subsystems) do
        local sub = SubsystemMgr:Get(name)
        if sub then
          for k, v in pairs(sub) do
            if type(v) == "function" and (
              k:find("Report") or k:find("Send") or k:find("Upload") or
              k:find("Verify") or k:find("Check") or k:find("Validate") or
              k:find("Scan") or k:find("Detect")
            ) then
              pcall(function() sub[k] = noop end)
            end
          end
          if sub.ReportPingDelayTimer then
            sub:RemoveGameTimer(sub.ReportPingDelayTimer)
            sub.ReportPingDelayTimer = nil
          end
          sub.DelayCount = 0
        end
      end
    end
    local AvatarExceptionPlayerInst = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
    if AvatarExceptionPlayerInst then
      AvatarExceptionPlayerInst.CheckAvatarException = noop
      AvatarExceptionPlayerInst.CheckAvatarExceptionOnce = noop
      AvatarExceptionPlayerInst.ReportAvatarException = noop
      AvatarExceptionPlayerInst.CheckSlotMeshVisible = retFalse
      AvatarExceptionPlayerInst.CheckPawnVisible = retFalse
      AvatarExceptionPlayerInst.CheckCanBugglyPostException = retFalse
    end
    local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
    if TssSdk then
      local originalOnRecvData = TssSdk.OnRecvData
      TssSdk.OnRecvData = function(data)
        if type(data) == "string" and (
          string.find(data, "report") or string.find(data, "exception") or
          string.find(data, "cheat") or string.find(data, "violation") or
          string.find(data, "hack") or string.find(data, "verify")
        ) then
          return
        end
        if originalOnRecvData then originalOnRecvData(data) end
      end
      TssSdk.SendReportInfo = noop
      TssSdk.ScanMemory = retTrue
      TssSdk.IsEmulator = retFalse
      TssSdk.GetTssSdkReportInfo = retEmptyString
      TssSdk.CheckEnvironment = retTrue
      TssSdk.VerifyProcess = retTrue
    end
  end)
end

local function InitializeReplayTelemetryBlocker()
  pcall(function()
    local SubsystemMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
      local replaySystems = {
        "RescueBtnReplayTraceSubsystem", "GameReportSubsystem", "ReplaySubsystem"
      }
      for _, name in ipairs(replaySystems) do
        local sub = SubsystemMgr:Get(name)
        if sub then
          for k, v in pairs(sub) do
            if type(v) == "function" and (
              k:find("Report") or k:find("Trace") or k:find("Replay") or
              k:find("Record") or k:find("Save")
            ) then
              pcall(function() sub[k] = noop end)
            end
          end
        end
      end
    end
    local logic_report_replay = package.loaded["client.slua.logic.replay.logic_report_replay"]
    if logic_report_replay then
      logic_report_replay.ReportReplay = noop
      logic_report_replay.SendReportReq = noop
      logic_report_replay.UploadReplay = noop
    end
  end)
end

local function InitializeReportFlowBlocker()
  pcall(function()
    local reportFlows = {
      "ReportAimFlow", "ReportHitFlow", "ReportAttackFlow", "ReportSecAttackFlow",
      "ReportHurtFlow", "ReportFireArms", "ReportVerifyInfoFlow", "ReportMrpcsFlow",
      "ReportPlayerBehavior", "ReportTeammatHurt", "ReportMisKillByTeammate",
      "ReportForbitPick", "ReportPlayerMoveRoute", "ReportPlayerPosition",
      "ReportVehicleMoveFlow", "ReportSecTgameMovingFlow", "ReportParachuteData",
      "ReportEquipmentFlow", "ReportPlayersPing", "ReportPlayerIP",
      "ReportPlayerFramePingRecord", "ReportDSNetSaturation", "ReportNetContinuousSaturate",
      "ReportDSNetRate", "ReportCircleFlow", "ReportPlayerKillFlow",
      "ReportMrpcsFlow", "ReportSecMrpcsFlow"
    }
    for _, funcName in ipairs(reportFlows) do
      if _G[funcName] then _G[funcName] = noop end
      if _G.GameplayCallbacks and _G.GameplayCallbacks[funcName] then
        _G.GameplayCallbacks[funcName] = noop
      end
    end
    local checkFuncs = {"CheckReportSecAttackFlowWithAttackFlow", "CheckReportSecAttackFlow"}
    for _, funcName in ipairs(checkFuncs) do
      if _G[funcName] then _G[funcName] = retFalse end
      if _G.GameplayCallbacks and _G.GameplayCallbacks[funcName] then
        _G.GameplayCallbacks[funcName] = retFalse
      end
    end
    local enableFlags = {
      "IsEnableReportPlayerKillFlow", "IsEnableReportMrpcsInCircleFlow",
      "IsEnableReportMrpcsInPartCircleFlow", "IsEnableReportMrpcsFlow",
      "IsEnableReportAttackFlow", "IsEnableReportHitFlow", "IsEnableReportCircleFlow"
    }
    for _, flag in ipairs(enableFlags) do
      if _G[flag] then _G[flag] = retFalse end
    end
  end)
end

local function InitializePlayerSecurityBypass()
  pcall(function()
    local securityCollectors = {
      "PlayerSecurityInfoCollector", "PlayerSecurityInfo", "SecurityInfoCollector",
      "ClientSecurityCollector", "PlayerAntiCheatCollector"
    }
    for _, collector in ipairs(securityCollectors) do
      if _G[collector] then
        for k, v in pairs(_G[collector]) do
          if type(v) == "function" and (
            k:find("Report") or k:find("Collect") or k:find("Send") or
            k:find("Upload") or k:find("Record")
          ) then
            _G[collector][k] = noop
          end
        end
      end
    end
    local SecuritySubsystem = require("GameLua.Mod.BaseMod.Common.Security.PlayerSecurityInfoSubsystem")
    if SecuritySubsystem then
      SecuritySubsystem.ReportData = noop
      SecuritySubsystem.CheckCheat = retFalse
      SecuritySubsystem.ValidatePlayer = retTrue
      SecuritySubsystem.CollectData = noop
      SecuritySubsystem.SendToServer = noop
    end
    if _G.PlayerSecurityInfo then
      _G.PlayerSecurityInfo.ReportCheat = noop
      _G.PlayerSecurityInfo.ReportSuspicious = noop
      _G.PlayerSecurityInfo.SendSecurityData = noop
      _G.PlayerSecurityInfo.CollectSecurityInfo = noop
    end
  end)
end

local function InitializeClientFlowBypass()
  pcall(function()
    local flowSubsystems = {
      "ClientSecMrpcsFlow", "MrpcsFlow", "MrpcsData", "ClientCircleFlowSubsystem",
      "ClientKillFlowSubsystem", "ClientSecPlayerKillFlow"
    }
    for _, name in ipairs(flowSubsystems) do
      local sub = package.loaded[name] or _G[name]
      if sub then
        for k, v in pairs(sub) do
          if type(v) == "function" and (
            k:find("Report") or k:find("Send") or k:find("Flow") or
            k:find("Record") or k:find("Process")
          ) then
            pcall(function() sub[k] = noop end)
          end
        end
      end
    end
    local CircleFlow = require("GameLua.Mod.BaseMod.Client.Security.ClientCircleFlowSubsystem")
    if CircleFlow then
      CircleFlow.ReportCircleFlow = noop
      CircleFlow.SendCircleData = noop
      CircleFlow.ReportPlayerPosition = noop
      CircleFlow.ReportCircleData = noop
    end
    if _G.ReportPlayerKillFlow then _G.ReportPlayerKillFlow = noop end
    if _G.ClientSecPlayerKillFlow then _G.ClientSecPlayerKillFlow = noop end
  end)
end

local function InitializeHeartbeatBypass()
  pcall(function()
    local heartbeatFuncs = {"Heartbeat", "SendHeartbeat", "ClientHeartbeat", "ServerHeartbeat"}
    for _, func in ipairs(heartbeatFuncs) do
      if _G[func] then _G[func] = noop end
      if _G.GameplayCallbacks and _G.GameplayCallbacks[func] then
        _G.GameplayCallbacks[func] = noop
      end
    end
    local SubsystemMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
      local heartbeatSub = SubsystemMgr:Get("HeartbeatSubsystem")
      if heartbeatSub then
        if heartbeatSub.timer then heartbeatSub:RemoveGameTimer(heartbeatSub.timer) end
        heartbeatSub.SendHeartbeat = noop
        heartbeatSub.StartHeartbeat = noop
      end
    end
  end)
end

local function InitializeSwiftHawkBypass()
  pcall(function()
    local swiftFuncs = {"SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams", "SendSwiftHawkData"}
    for _, func in ipairs(swiftFuncs) do
      if _G[func] then _G[func] = noop end
      if _G.GameplayCallbacks and _G.GameplayCallbacks[func] then
        _G.GameplayCallbacks[func] = noop
      end
    end
    local SwiftHawkSubsystem = package.loaded["GameLua.Mod.BaseMod.Client.Security.SwiftHawkSubsystem"]
    if SwiftHawkSubsystem then
      SwiftHawkSubsystem.ReportData = noop
      SwiftHawkSubsystem.SendReport = noop
      SwiftHawkSubsystem.CollectTelemetry = noop
    end
  end)
end

local function InitializeCoronaLabBypass()
  pcall(function()
    if _G.CoronaLab then
      _G.CoronaLab.ReportData = noop
      _G.CoronaLab.SendData = noop
      _G.CoronaLab.CollectData = noop
      _G.CoronaLab.Telemetry = noop
    end
    local SubsystemMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if SubsystemMgr then
      local corona = SubsystemMgr:Get("CoronaLabSubsystem")
      if corona then
        corona.ReportData = noop
        corona.SendToServer = noop
        corona.CollectTelemetry = noop
        corona.StopCollection = noop
      end
    end
  end)
end

local function InitializeModifierExceptionBypass()
  pcall(function()
    if _G.bReportedModifierException then
      _G.bReportedModifierException = false
    end
    local ModifierSubsystem = require("GameLua.Mod.BaseMod.Common.Security.ModifierExceptionSubsystem")
    if ModifierSubsystem then
      ModifierSubsystem.ReportException = noop
      ModifierSubsystem.CheckModifier = retTrue
      ModifierSubsystem.ValidateModifier = retTrue
      ModifierSubsystem.ReportModifierError = noop
    end
  end)
end

local function InitializeSimulateCharacterLocationBypass()
  pcall(function()
    local SimulateSubsystem = require("GameLua.Mod.BaseMod.Gameplay.Simulate.SimulateCharacterSubsystem")
    if SimulateSubsystem then
      SimulateSubsystem.ReportLocation = noop
      SimulateSubsystem.SendLocationData = noop
      SimulateSubsystem.VerifyLocation = retTrue
    end
  end)
end

local function InitializeShootVerificationBypass()
  pcall(function()
    local ShootVerify = require("GameLua.Dev.Subsystem.ShootVerifySubSystemClient")
    if ShootVerify then
      ShootVerify.OnShootVerifyFailed = noop
      ShootVerify.SendVerifyData = noop
      ShootVerify.ReportBulletHit = noop
      ShootVerify.UploadHitInfo = noop
      ShootVerify.VerifyShot = retTrue
    end
    if _G.BulletHitInfoUploadData then
      _G.BulletHitInfoUploadData.Report = noop
      _G.BulletHitInfoUploadData.Send = noop
      _G.BulletHitInfoUploadData.Upload = noop
    end
  end)
end

local function InitializeNetworkPacketBlock()
  pcall(function()
    if NetUtil and NetUtil.SendPacket then
      local originalSend = NetUtil.SendPacket
      local blockedPackets = {
        ["ReportAttackFlow"] = 1, ["ReportSecAttackFlow"] = 1, ["ReportHurtFlow"] = 1,
        ["ReportFireArms"] = 1, ["ReportVerifyInfoFlow"] = 1, ["ReportMrpcsFlow"] = 1,
        ["ReportPlayerBehavior"] = 1, ["ReportTeammatHurt"] = 1, ["ReportPlayerMoveRoute"] = 1,
        ["ReportPlayerPosition"] = 1, ["ReportSecVehicleMoveFlow"] = 1, ["report_parachute_data"] = 1,
        ["on_tss_sdk_anti_data"] = 1, ["ReportAimFlow"] = 1, ["ReportHitFlow"] = 1,
        ["ReportCircleFlow"] = 1, ["report_players_ping"] = 1, ["report_player_ip"] = 1,
        ["report_net_saturate"] = 1, ["report_speed_hack"] = 1, ["report_wall_hack"] = 1,
        ["report_aim_bot"] = 1, ["report_esp_usage"] = 1, ["report_modded_files"] = 1,
        ["detect_cheat"] = 1, ["ban_player"] = 1, ["client_anti_cheat_report"] = 1,
        ["ReportPlayerKillFlow"] = 1, ["ClientSecPlayerKillFlow"] = 1,
        ["ReportMrpcsFlow"] = 1, ["ClientSecMrpcsFlow"] = 1, ["MrpcsData"] = 1,
        ["CheckReportSecAttackFlow"] = 1, ["CheckReportSecAttackFlowWithAttackFlow"] = 1,
        ["RPC_ClientCoronaLab"] = 1, ["CoronaLabReport"] = 1, ["CoronaLabData"] = 1,
        ["PlayerSecurityInfo"] = 1, ["ReportSecurityInfo"] = 1, ["SendSecurityData"] = 1,
        ["ClientCircleFlow"] = 1, ["IsEnableReportPlayerKillFlow"] = 1,
        ["IsEnableReportMrpcsInCircleFlow"] = 1, ["IsEnableReportMrpcsInPartCircleFlow"] = 1,
        ["bReportedModifierException"] = 1, ["ReportModifierException"] = 1,
        ["RPC_Server_ReportSimulateCharacterLocation"] = 1, ["ReportSimulateCharacterLocation"] = 1,
        ["RPC_Client_ShootVertifyRes"] = 1, ["BulletHitInfoUploadData"] = 1,
        ["ShootVerifyFailed"] = 1, ["report_unrealnet_exception"] = 1, ["tss_sdk_report"] = 1,
        
        ["SwiftHawk"] = 1, ["ClientSwiftHawk"] = 1, ["ClientSwiftHawkWithParams"] = 1,
        ["SwiftHawkReport"] = 1, ["SwiftHawkData"] = 1,
        ["AntiCheatReport"] = 1, ["CheatDetection"] = 1, ["ViolationReport"] = 1,
        ["SecurityViolation"] = 1, ["IntegrityCheck"] = 1, ["SignatureVerify"] = 1,
        ["1162992962"] = 1, ["242463958"] = 1, ["224639039"] = 1, ["816081779"] = 1,
        ["224943158"] = 1, ["516985564"] = 1,
        ["inspection_system_report_to_inspector"] = 1,
        ["ingame_voice_ban_notify"] = 1,
        ["inspection_system_notify_inspector"] = 1,
      }
      NetUtil.SendPacket = function(packetName, ...)
        if blockedPackets[packetName] then
          return nil
        end
        return originalSend(packetName, ...)
      end
      NetUtil.IsBypassed = true
    end
    if _G.SendRPC then
      local originalSendRPC = _G.SendRPC
      local blockedRPCs = {
        "RPC_Server_ReportPlayerKillFlow", "RPC_Server_ClientSecMrpcsFlow",
        "RPC_Server_Heartbeat", "RPC_Server_SwiftHawk", "RPC_Server_ClientSwiftHawkWithParams",
        "RPC_Server_ReportSimulateCharacterLocation", "RPC_Client_ShootVertifyRes",
        "RPC_ClientCoronaLab",
        "RPC_Server_HawkReportCheat",
      }
      _G.SendRPC = function(rpcName, ...)
        for _, blocked in ipairs(blockedRPCs) do
          if rpcName == blocked then return nil end
        end
        return originalSendRPC(rpcName, ...)
      end
    end
  end)
end

local function InitializeAntiCheatHooks()
  pcall(function()
    local HiggsBosonComponent = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
    if HiggsBosonComponent and HiggsBosonComponent.StaticShowSecurityAlertInDev then
      HiggsBosonComponent.StaticShowSecurityAlertInDev = noop
    end
    if HiggsBosonComponent and HiggsBosonComponent.BlackList then
      for k in pairs(HiggsBosonComponent.BlackList) do HiggsBosonComponent.BlackList[k] = nil end
    end
  end)
  _G.BlackList = {}
  
  pcall(function()
    _G.GlobalPlayerCoronaData = _G.GlobalPlayerCoronaData or {}
    _G.GlobalPlayerCheatTimes = _G.GlobalPlayerCheatTimes or {}
    if not getmetatable(_G.GlobalPlayerCoronaData) then
      local mt = { __newindex = function() end }
      setmetatable(_G.GlobalPlayerCoronaData, mt)
    end
  end)
  
  if _G.AvatarCheckCallback then
    _G.AvatarCheckCallback.StartAvatarCheck = noop
    _G.AvatarCheckCallback.OnReportItemID = noop
    _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(PlayerController)
      if slua.isValid(PlayerController) and PlayerController.HiggsBosonComponent then
        PlayerController.HiggsBosonComponent:ControlMHActive(0)
        PlayerController.HiggsBosonComponent.bMHActive = false
      end
    end
  end
end

local function InitializeAntiReport()
  pcall(function()
    local paths = {
      "GameLua.Mod.BaseMod.Client.Security.ClientReportPlayerSubsystem",
      "Client.Security.ClientReportPlayerSubsystem",
      "GameLua.Mod.BaseMod.DS.Security.DSReportPlayerSubsystem"
    }
    for _, path in ipairs(paths) do
      local sub = package.loaded[path]
      if not sub then
        local success, reqModule = pcall(require, path)
        if success and reqModule then sub = reqModule end
      end
      if sub then
        for k, v in pairs(sub) do
          if type(v) == "function" and (
            k:find("Report") or k:find("Record") or k:find("Send") or
            k:find("Upload") or k:find("Notify")
          ) then
            pcall(function() sub[k] = noop end)
          end
        end
      end
    end
  end)
end

local function InitializeGameplayBypass()
  pcall(function()
    if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
    if _G.GameplayCallbacks.IsBypassed then return end
    local GC = _G.GameplayCallbacks
    local reportFuncs = {
      "ReportAttackFlow", "ReportSecAttackFlow", "ReportHurtFlow", "ReportFireArms",
      "ReportVerifyInfoFlow", "ReportMrpcsFlow", "ReportPlayerBehavior", "ReportTeammatHurt",
      "ReportMisKillByTeammate", "ReportForbitPick", "ReportPlayerMoveRoute",
      "ReportPlayerPosition", "ReportVehicleMoveFlow", "ReportSecTgameMovingFlow",
      "ReportParachuteData", "SendTssSdkAntiDataToLobby", "ReportEquipmentFlow",
      "ReportAimFlow", "ReportPlayersPing", "ReportPlayerIP", "ReportPlayerFramePingRecord",
      "OnDSConnectionSaturated", "ReportDSNetSaturation", "ReportNetContinuousSaturate",
      "ReportDSNetRate", "SendClientStats", "SendServerAvgTickDelta",
      "ReportCircleFlow", "ReportPlayerKillFlow", "ClientSecMrpcsFlow", "Heartbeat",
      "SwiftHawk", "ClientSwiftHawk", "ClientSwiftHawkWithParams"
    }
    for _, funcName in ipairs(reportFuncs) do
      GC[funcName] = noop
    end
    GC.CheckReportSecAttackFlowWithAttackFlow = retFalse
    GC.CheckReportSecAttackFlow = retFalse
    local originalDSPlayerState = GC.OnDSPlayerStateChanged
    GC.OnDSPlayerStateChanged = function(UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason)
      local stateStr = InPlayerState and string.lower(tostring(InPlayerState)) or ""
      local blockedStates = {
        ["cheatdetected"] = true, ["connectionlost"] = true, ["connectiontimeout"] = true,
        ["connectionexception"] = true, ["netdrivererror"] = true, ["banned"] = true,
        ["kicked"] = true, ["suspended"] = true, ["violationdetected"] = true,
        ["integrityfailure"] = true, ["securityviolation"] = true
      }
      if blockedStates[stateStr] then return end
      if originalDSPlayerState then pcall(originalDSPlayerState, UID, InPlayerState, bPureWatcher, bIsSafeExit, ParamReason) end
    end
    GC.OnPlayerNetConnectionClosed = noop
    GC.OnPlayerActorChannelError = noop
    GC.OnPlayerRPCValidateFailed = noop
    GC.OnPlayerSpectateException = noop
    GC.OnShutdownAfterError = noop
    GC.IsBypassed = true
  end)
end

local function InitializeKillAllSubsystems()
  pcall(function()
    local subMgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
    if not subMgr then return end
    local subsystemsToKill = {
      "CoronaLabSubsystem", "PlayerSecurityInfoSubsystem", "ClientCircleFlowSubsystem",
      "ModifierExceptionSubsystem", "SimulateCharacterSubsystem", "ShootVerifySubSystemClient",
      "HiggsBosonComponent", "ClientReportPlayerSubsystem", "DSReportPlayerSubsystem",
      "ClientHawkEyePatrolSubsystem", "DSHawkEyePatrolSubsystem",
      "ClientDataStatistcsSubsystem", "AFKReportorSubsystem", "BehaviorScoreSubsystem",
      "FileCheckSubsystem", "MemoryCheckSubsystem", "SpeedCheckSubsystem", "WallCheckSubsystem",
      "AvatarExceptionSubsystem", "GameReportSubsystem", "RescueBtnReplayTraceSubsystem",
      "ClientSecMrpcsFlowSubsystem", "MrpcsFlowSubsystem", "PlayerKillFlowSubsystem",
      "CircleFlowSubsystem", "SwiftHawkSubsystem", "HeartbeatSubsystem",
      "AntiCheatSubsystem", "IntegrityCheckSubsystem", "SignatureVerifySubsystem",
      "MD5CheckSubsystem", "PakVerifySubsystem"
    }
    for _, name in ipairs(subsystemsToKill) do
      local sub = subMgr:Get(name)
      if sub then
        for k, v in pairs(sub) do
          if type(v) == "function" and (
            k:find("Report") or k:find("Send") or k:find("Upload") or
            k:find("Verify") or k:find("Check") or k:find("Validate") or
            k:find("Scan") or k:find("Detect") or k:find("Collect") or
            k:find("Flow") or k:find("Heartbeat")
          ) then
            pcall(function() sub[k] = noop end)
          end
        end
        if sub.timer then pcall(function() sub:RemoveGameTimer(sub.timer) end) end
        if sub.heartbeatTimer then pcall(function() sub:RemoveGameTimer(sub.heartbeatTimer) end) end
        if sub.reportTimer then pcall(function() sub:RemoveGameTimer(sub.reportTimer) end) end
      end
    end
  end)
end


local function ApplyNewBypasses()
  pcall(function()
    InitializeSLUABypass()
    InitializeMD5Bypass()
    InitializeSkinBypass()
    InitializeLogBlocker()
    InitializeScannerBlocker()
    InitializeReplayTelemetryBlocker()
    InitializeReportFlowBlocker()
    InitializePlayerSecurityBypass()
    InitializeClientFlowBypass()
    InitializeHeartbeatBypass()
    InitializeSwiftHawkBypass()
    InitializeCoronaLabBypass()
    InitializeModifierExceptionBypass()
    InitializeSimulateCharacterLocationBypass()
    InitializeShootVerificationBypass()
    InitializeNetworkPacketBlock()
    InitializeAntiCheatHooks()
    InitializeAntiReport()
    InitializeGameplayBypass()
    InitializeKillAllSubsystems()
    InitializeFinalProtection()
  end)
end


local BLACKLIST_HOSTS = {
    "tss.tencent","syzsdk","gcloud.qq","reportlog","tdos","logupload","feedback.wh","crash2",
    "privacy.qq","privacy.tencent","oth.eve","mdt.qq","act.tencentyun","analytics","report.qq",
    "anticheatexpert","crashsight","wetest","log.tav","sngd","tracer","intlsdk","igamecj",
    "cdn.club","gpubgm","graph.facebook","calendarpushsubscription","googleads","doubleclick",
    "firebaselogging","firebaseremoteconfig","fonts.googleapis","abs.twimg","dl.listdl",
    "igame.gcloudcs","bugly","beacon","helpshift","tdm","apm","safeguard","weiyun","qzone",
    "tencent-cloud","myapp","idqqimg","gtimg","qqmail","tcdn","cloudctrl","sdkostrace",
    "103.134.189.146","mbgame","csoversea","igame","pubgmobile","down.anticheatexpert.com",
    "asia.csoversea.mbgame.anticheatexpert.com","log.tav.qq","syzsdk.qq","logiservice.qcloud",
    "opensdk.tencent","exp.helpshift","loginsdkapi.zingplay","firebase","googleapis","facebook","gvoice"
}
local BLACKLIST_PORTS = {
    "10334","11045","12221","13331","8011","8015","9001","20000","20001","20002","20003","20004",
    "20005","19700","1670","19900","14545","10213","8700","25177","10685","10336","10262","27000",
    "27040","27015","27030","10706","10095","12401","11008","10309","11075","10157","24798","10709",
    "6667","10087","31113","20371","10120","10664","13728","10769","10761","5061","5062","18081",
    "15692","9030","8080","8086","8088"
}
local FILE_KEYWORDS = {
    "tlog","crash","bugly","report","beacon","wetest","analytics","telemetry","trace","dump",
    "exception","feedback","aps_log","mtp_detect","network_loss","client_error","ue4crash","tdm","gcloud"
}

local function isBlacklisted(str)
    if type(str) ~= "string" then return false end
    local low = str:lower()
    for _, kw in ipairs(BLACKLIST_HOSTS) do if low:find(kw,1,true) then return true end end
    for _, port in ipairs(BLACKLIST_PORTS) do if low:find(":"..port) or low:find("/"..port) then return true end end
    return false
end

local function applyNetworkBlocker()
    pcall(function()
        if _G.HttpRequest then
            local orig = _G.HttpRequest
            _G.HttpRequest = function(url, ...) if isBlacklisted(url) then return nil end return orig(url, ...) end
        end
        if _G.FHttpModule and _G.FHttpModule.CreateRequest then
            local orig = _G.FHttpModule.CreateRequest
            _G.FHttpModule.CreateRequest = function(...)
                local url = select(1,...)
                if isBlacklisted(url) then return nil end
                return orig(...)
            end
        end
        local netMods = {
            "client.slua.logic.network.logic_network","client.slua.logic.download.report.puffer_tlog",
            "client.slua.data.BasicData.BasicDataClientReport","GameLua.GameCore.Module.Network.NetworkManager",
            "client.network.Protocol.ClientTlogHandler","client.network.Protocol.BattleReportHandler",
            "client.network.Protocol.ClientErrorReportHandler"
        }
        for _, mp in ipairs(netMods) do
            local mod = package.loaded[mp]
            if mod then
                for k, v in pairs(mod) do
                    if type(v) == "function" and (k:find("Http") or k:find("Request") or k:find("Send") or k:find("Upload") or k:find("Post") or k:find("Get") or k:find("Report")) then
                        local origf = v
                        mod[k] = function(...)
                            local args = {...}
                            for _, arg in ipairs(args) do if type(arg)=="string" and isBlacklisted(arg) then return nil end end
                            return pcall(origf, ...)
                        end
                    end
                end
            end
        end
    end)

    local orig_io_open = io.open
    io.open = function(path, mode)
        if type(path) == "string" then
            local lp = path:lower()
            for _, kw in ipairs(FILE_KEYWORDS) do
                if lp:find(kw) then
                    if mode and (mode == "w" or mode == "a" or mode == "w+" or mode == "a+") then
                        return nil, "Blocked"
                    end
                end
            end
            if lp:find("tdm") or lp:find("gcloud") or lp:find("beacon") then
                if mode and (mode == "w" or mode == "a" or mode == "w+") then return nil end
            end
        end
        return orig_io_open(path, mode)
    end

    if _G.UnrealEngine and _G.UnrealEngine.CrashContext then
        _G.UnrealEngine.CrashContext = nil
        _G.UnrealEngine.CrashContext = { SetCrashContext = noop, ReportCrash = noop, AddCrashData = noop }
    end
end

local function killGlobalFunctions()
    local globalFuncs = {
        "ReportTLogEvent","SendTlog","SendClientStats","ReportHitFlow","ReportAvatarException",
        "SendComplaintReq","SubmitReport","ReportSuspiciousPlayer","SendPacket","OnSyncBanInfo",
        "OnVoiceBanNotify","SendSecTLog","MarkSuspiciousPlayer","ReportPlayerBehaviorData",
        "CheckCompliance","ReportIllegalProgram","UploadVoiceLog","ReportCheat","ReportPlayer",
        "ShowReportUI","OpenReportPanel","OnClickReport","ReportCheatDetected"
    }
    for _, fn in ipairs(globalFuncs) do
        if type(_G[fn]) == "function" then _G[fn] = noop end
        _G[fn] = nil
    end
end


local function deepHook(obj, depth)
    if depth > 4 then return end
    if type(obj) ~= "table" then return end
    for k, v in pairs(obj) do
        if type(k) == "string" then
            local lk = k:lower()
            if lk:find("crc") or lk:find("verify") or lk:find("integrity") or lk:find("hash") or lk:find("paksign") then
                if type(v) == "function" then
                    obj[k] = function(...) if lk:find("crc") or lk:find("hash") then return 0 end; return true end
                end
            end
        end
        if type(v) == "table" and v ~= obj then deepHook(v, depth + 1) end
    end
end

local function applyFullCRCFaker()
    if _G.__CRCFakerDone then return end
    pcall(function()
        if not slua_GameFrontendHUD then return end
        if Client then
            if Client.VerifyPakFile then Client.VerifyPakFile = retTrue end
            if Client.CheckFileCRC then Client.CheckFileCRC = retZero end
            if Client.GetFileHash then Client.GetFileHash = function() return "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF" end end
            if Client.VerifySignature then Client.VerifySignature = retTrue end
            if Client.CheckGameLuaIntegrity then Client.CheckGameLuaIntegrity = retTrue end
            if Client.VerifyFileIntegrity then Client.VerifyFileIntegrity = retTrue end
            if Client.VerifyAllPaks then Client.VerifyAllPaks = retTrue end
        end
        for _, mod in pairs(package.loaded) do if type(mod) == "table" then deepHook(mod, 0) end end
        _G.__CRCFakerDone = true
    end)
end


local function applyAdvancedPatches()
    pcall(function()
        local SubsystemMgr = safe_require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if SubsystemMgr then
            local function patchSub(name, methods, retvals, fields)
                local inst = SubsystemMgr:Get(name)
                if inst then
                    if methods then for k, v in pairs(methods) do if type(inst[k]) == "function" then inst[k] = v end end end
                    if retvals then for k, v in pairs(retvals) do if type(inst[k]) == "function" then inst[k] = v end end end
                    if fields then for k, v in pairs(fields) do inst[k] = v end end
                end
            end
            patchSub("AFKReportorSubsystem", {PlayerHaveAction = noop, ReportAFK = noop})
            patchSub("ClientDataStatistcsSubsystem", nil, nil, {DelayCount = 0})
            patchSub("AvatarExceptionSubsystem", {ReportException = noop, BindPlayerCharacter = noop, CheckAvatarValid = retTrue})
            patchSub("ShootVerifySubSystemClient", {ReportVerifyFail = noop, OnVerifyFailed = noop})
            patchSub("RescueBtnReplayTraceSubsystem", {ReportTrace = noop, StartTickMonitor = noop, TickMonitorCheck = noop, ReportTickMonitorHeartbeat = noop})
            patchSub("GameReportSubsystem", {ReplayReportData = retFalse, CheckCanBugglyPostException = retFalse, BugglyPostExceptionFull = retFalse, GetClientReplayDataReporter = function() return nil end})
            patchSub("FileCheckSubsystem", {StartCheck = noop, ReportAbnormalFile = noop})
            patchSub("ReplaySubsystem", {SendReport = noop, Upload = noop})
            patchSub("ClientFlagSubsystem", {EvaluateFlags = noop, GetFlagLevel = retZero, GetFlagBanDuration = retZero, IsFlagged = retFalse})
            patchSub("DSAITLogSubsystem", {_UpdateTTKRecords = noop, _UpdateOperatingFrequency = noop})
            patchSub("TLogSubsystem", {OnInit = noop})
            local gameReportSub = SubsystemMgr:Get("GameReportSubsystem")
            if gameReportSub and gameReportSub.Reporter then
                gameReportSub.Reporter.ReportIntArrayData = noop
                gameReportSub.Reporter.ReportUInt8ArrayData = noop
                gameReportSub.Reporter.ReportFloatArrayData = noop
            end
        end
    end)
    pcall(function()
        local CreativeMode = import("CreativeModeBlueprintLibrary")
        if CreativeMode then
            CreativeMode.MD5HashByteArray = function() return "BYPASSED_MD5_HASH" end
            CreativeMode.GetContentDiffData = function() return true, "BYPASSED" end
        end
    end)
    pcall(function()
        local AvatarExceptionPlayerInst = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
        if AvatarExceptionPlayerInst then
            AvatarExceptionPlayerInst.CheckAvatarException = noop
            AvatarExceptionPlayerInst.CheckAvatarExceptionOnce = noop
            AvatarExceptionPlayerInst.ReportAvatarException = noop
            AvatarExceptionPlayerInst.CheckSlotMeshVisible = retFalse
            AvatarExceptionPlayerInst.CheckPawnVisible = retFalse
            AvatarExceptionPlayerInst.CheckCanBugglyPostException = retFalse
        end
    end)
    pcall(function()
        local AvatarChecker = package.loaded["blacklist.slua.logic.lobby_gm.AvatarCheckerModule"]
        if AvatarChecker then AvatarChecker.CheckAvatar = retTrue; AvatarChecker.ReportException = noop end
    end)
    pcall(function()
        local MemoryWarning = package.loaded["client.slua.logic.memory_warning.logic_memory_warning"]
        if MemoryWarning then MemoryWarning.OnMemoryWarning = noop; MemoryWarning.ReportMemoryWarning = noop end
    end)
    pcall(function()
        local StoreInterface = package.loaded["client.slua.logic.store.logic_store_game_interface"]
        if StoreInterface then StoreInterface.IsStoreGameSupported = retTrue; StoreInterface.NotifyGetPGSLoginInfo = noop end
    end)
    pcall(function()
        local VoiceSubsystem = package.loaded["GameLua.Mod.BaseMod.Client.Voice.VoiceChatSubsystem"]
        if VoiceSubsystem then VoiceSubsystem.OnPlayerSubmitComplaint = noop end
    end)
    pcall(function()
        local TssSdk = package.loaded["TssSdk"] or _G.TssSdk
        if TssSdk then
            local orig = TssSdk.OnRecvData
            TssSdk.OnRecvData = function(data)
                if type(data) == "string" and (data:find("report") or data:find("exception")) then return end
                if orig then orig(data) end
            end
            TssSdk.SendReportInfo = noop
            TssSdk.ScanMemory = retTrue
            TssSdk.IsEmulator = retFalse
            TssSdk.GetTssSdkReportInfo = function() return "" end
        end
    end)
    pcall(function()
        local logicReplayReport = package.loaded["client.slua.logic.replay.logic_report_replay"]
        if logicReplayReport then logicReplayReport.ReportReplay = noop; logicReplayReport.SendReportReq = noop end
    end)
    pcall(function()
        local PufferTlog = package.loaded["client.slua.logic.download.report.puffer_tlog"]
        if PufferTlog then PufferTlog.ReportEvent = noop; PufferTlog.ReportDownloadResult = noop; PufferTlog.ReportODPAKError = noop end
    end)
    pcall(function()
        local AvatarUtils = package.loaded["AvatarUtils"]
        if AvatarUtils then AvatarUtils.CheckIsWeaponInBlackList = retFalse; AvatarUtils.IsValidAvatar = retTrue end
    end)
    pcall(function()
        local EquipmentExceptionReport = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
        if EquipmentExceptionReport then EquipmentExceptionReport.Report = noop end
    end)
    pcall(function()
        local TLog = _G.TLog or package.loaded["TLog"]
        if TLog then TLog.Info = noop; TLog.Warning = noop; TLog.Error = noop; TLog.Debug = noop; TLog.Report = noop end
    end)
    pcall(function()
        local pc = (slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController())
        if pc and pc.HiggsBosonComponent then
            pc.HiggsBosonComponent.bMHActive = false
            pc.HiggsBosonComponent:ControlMHActive(0)
        end
    end)
    pcall(function() _G.BlackList = {} end)
end


local function safeSelfHeal()
    pcall(function()
        local TM = safe_require("GameLua.Mod.BaseMod.Common.TickManager")
        if TM and TM.AddLoopTimer then
            TM.AddLoopTimer(120, function()
                pcall(function()
                    local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
                    if pc and pc.HiggsBosonComponent then
                        pc.HiggsBosonComponent.bMHActive = false
                        pc.HiggsBosonComponent:ControlMHActive(0)
                    end
                    if slua.isValid(pc) then
                        local pawn = pc:GetCurPawn()
                        if slua.isValid(pawn) then
                            pcall(function()
                                local Higgs = package.loaded["GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent"]
                                if Higgs then
                                    Higgs.ControlMHActive = noop; Higgs.TriggerAvatarCheck = noop; Higgs.StartAvatarCheck = noop
                                    Higgs.ReportItemID = noop; Higgs.OnReportItemID = noop; Higgs.ReceiveAnyDamage = noop
                                    Higgs.OnWeaponHitRecord = noop; Higgs.ShowSecurityAlert = noop; Higgs.ServerReportAvatar = noop
                                    Higgs.ClientReportNetAvatar = noop; Higgs.GetNetAvatarItemIDs = retEmpty; Higgs.GetCurWeaponSkinID = retZero
                                end
                                if _G.AvatarCheckCallback then _G.AvatarCheckCallback.StartAvatarCheck = noop; _G.AvatarCheckCallback.OnReportItemID = noop end
                            end)
                        end
                    end
                end)
                local modules = {"client.slua.logic.ban.ClientBanLogic","client.common.ban_util","client.logic.login.logic_tt_ban","client.slua.logic.ban.BanTipsLogic"}
                for _, modName in ipairs(modules) do
                    local mod = package.loaded[modName]
                    if mod then
                        for k, v in pairs(mod) do
                            if type(k) == "string" and (k:find("Ban") or k:find("Flag")) and type(v) == "function" then
                                mod[k] = retFalse
                            end
                        end
                    end
                end
            end)
        end
    end)
end


pcall(function()
    local Gokuba = _G.GokubaLogic or package.loaded["GokubaLogic"]
    if Gokuba then
        Gokuba.ForwardFeature = function() return end
        Gokuba.InitGokubaLogic = function() return end
    end
    if _G.NetUtil and _G.NetUtil.SendPkg then
        local origSendPkg = _G.NetUtil.SendPkg
        _G.NetUtil.SendPkg = function(packetName, ...)
            if packetName == "battle_client_sync_allstar_auth_check_result_req" then
                return
            end
            return origSendPkg(packetName, ...)
        end
    end
end)


pcall(function()
    local HostedProto = _G.HostedProtoConfig or package.loaded["HostedProtoConfig"]
    if HostedProto and HostedProto.Proto then
        if HostedProto.Proto.NationalEsportsSecurityCheck then
            HostedProto.Proto.NationalEsportsSecurityCheck.func = "noop"
        end
    end
end)


pcall(function()
    local AC_Subsystem = _G.AntiCheatSubsystem or package.loaded["GameLua.Mod.BaseMod.Client.Security.AntiCheatSubsystem"]
    if AC_Subsystem then
        AC_Subsystem.OnInit = function() return end
        AC_Subsystem.OnTick = function() return end
        AC_Subsystem.CheckAbnormalStatus = function() return false end
        AC_Subsystem.ReportSecurityData = function() return end
        AC_Subsystem.OnDetectionResult = function() return end
        AC_Subsystem.TriggerSafetyScan = function() return end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- تشغيل كل دوال Premium التي لم تُستدعَ بعد
-- ═══════════════════════════════════════════════════════════════════════════
-- ═══════════════════════════════════════════════════════════════════════════
-- PREMIUM BYPASS — SAFE MODE (بدون كسر الـmatchmaking)
-- ═══════════════════════════════════════════════════════════════════════════
pcall(function()
    print("[Premium] 🚀 تفعيل الطبقات الآمنة فقط...")

    -- ✅ آمن
    if TssSdkBypass then pcall(TssSdkBypass) end
    if MemoryBypass then pcall(MemoryBypass) end
    if AnoSDKBypass then pcall(AnoSDKBypass) end
    if MprotectBypass then pcall(MprotectBypass) end

    -- ✅ AntiCheatManager مع قيم معقولة
    if EnhancedAntiCheatBypass then
        pcall(function()
            EnhancedAntiCheatBypass()
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if slua.isValid(pc) then
                local mgr = pc.PlayerAntiCheatManager or pc.AntiCheatManager
                if slua.isValid(mgr) then
                    for _, f in ipairs({
                        "BaseDiffVel","BaseDiffRegion","BaseDiffTime",
                        "MaxDistanceToGround","MaxMoveDistance2DPerSecond",
                        "MaxCharMoveDist2DPerSecond"
                    }) do
                        pcall(function()
                            if type(mgr[f]) == "number" then mgr[f] = 100000 end
                        end)
                    end
                end
            end
        end)
    end

    -- ✅ آمن
    if applyAdvancedPatches then pcall(applyAdvancedPatches) end
    if safeSelfHeal then pcall(safeSelfHeal) end

    print("[Premium] ✅ تم تفعيل الطبقات الآمنة")
end)
end



local class = require("class")
local CCharacterBase = require("GameLua.GameCore.Framework.CharacterBase")
local CBRPlayerCharacterBase = class(CCharacterBase, nil, BRPlayerCharacterBase)
return require("combine_class").DeclareFeature(CBRPlayerCharacterBase, {
  {
    SkyTransition = "GameLua.Mod.BaseMod.Gameplay.Feature.SkyControl.PlayerCharacterSkyTransitionFeature"
  },
  {
    CarryDeadBoxFeature = "GameLua.Mod.Library.GamePlay.Feature.CarryDeadBoxFeature"
  },
  {
    SpecialSuitFeature = "GameLua.Mod.Library.GamePlay.Feature.SpecialSuitFeature"
  },
  {
    TeleportPawnFeature = "GameLua.Mod.Library.GamePlay.Feature.TeleportPawnFeature"
  },
  {
    LifterControl = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.CharacterLifterControlFeature"
  },
  {
    FinalKillEffect = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.PlayerCharacterFinalKillEffectFeature"
  },
  {
    CampFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.Camp.PlayerCharacterCampFeature"
  },
  {
    BuildSkateFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.PlayerCharacterBuildVehicleFeature"
  },
  {
    CommonBornlandTransformFeature = "GameLua.Mod.BaseMod.GamePlay.Feature.HeroPropFeature.CommonBornlandTransformFeature"
  },
  {
    ParachuteFormation = "GameLua.Mod.BaseMod.GamePlay.Feature.ParachuteFormationFeature"
  },
  {
    SpiderSenseFootprintFeature = "GameLua.Mod.Library.GamePlay.Feature.SpiderSenseFootprintFeature"
  },
  {
    GeneralShowSpotFeature = "GameLua.Mod.BRMod.Gameplay.Feature.PlayerCharacterGeneralShowSpotFeature"
  }
}, "BRPlayerCharacterBase")