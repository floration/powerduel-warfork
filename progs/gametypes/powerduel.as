/*
Power Duel for Warfork
Based on the Warsow/Warfork Duel gametype (Copyright (C) 2009-2010 Chasseur de bots), GPLv2+.

Rules:
 - 1v1, each player is their own team.
 - Each team starts with PD_TEAM_HP team HP (shown as the team score and as
   fighting-game style bars at the top of the HUD).
 - Every point of damage a player takes comes off their team HP, overkill
   included (a 300 quad rail takes 300). Picking up health/armor only
   refills your current life, never the team HP.
 - Team HP hits 0 = you lose. On time limit, more team HP wins.
 - At PD_QUAD_HP team HP or less you respawn with quad for that whole life.
 - Everyone spawns with every weapon and infinite ammo ("full attack").
 - Ammo pickups on the map are replaced with armor shards.
 - Nothing is dropped on death (no weapon drops, no backpacks).
*/

const float PD_TEAM_HP = 5000.0f;
const float PD_QUAD_HP = 500.0f;
const int PD_QUAD_REFILL = 30;       // quad timer is kept topped up to this while it lasts
const uint PD_SHARD_RESPAWN = 25000; // ms
const float PD_SHARD_ARMOR = 5.0f;
const float PD_SHARD_MAX = 200.0f;

float[] pdTeamHP( GS_MAX_TEAMS );
bool[] pdQuadLife( 256 );

int pdShardSound;
int pdShardModel;

///*****************************************************************
/// TEAM HP
///*****************************************************************

bool PD_IsPlaying()
{
    return match.getState() == MATCH_STATE_PLAYTIME;
}

void PD_ResetTracking()
{
    for ( int i = 0; i < maxClients; i++ )
    {
        pdQuadLife[i] = false;
    }
}

void PD_SetTeamHP( int team, float hp )
{
    if ( hp < 0.0f )
        hp = 0.0f;
    pdTeamHP[team] = hp;

    int shown = int( ceil( hp ) );
    Team @t = @G_GetTeam( team );
    t.stats.setScore( shown );
    for ( int j = 0; @t.ent( j ) != null; j++ )
        t.ent( j ).client.stats.setScore( shown );
}

// 0..100 for the HUD progress bars, never 0 while there is HP left (0 hides the bar)
int PD_Percent( int team )
{
    float hp = pdTeamHP[team];
    if ( hp <= 0.0f )
        return 0;
    int pct = int( ceil( hp * 100.0f / PD_TEAM_HP ) );
    if ( pct < 1 )
        pct = 1;
    if ( pct > 100 )
        pct = 100;
    return pct;
}

void PD_UpdateHUD()
{
    bool show = match.getState() >= MATCH_STATE_PLAYTIME;

    for ( int i = 0; i < maxClients; i++ )
    {
        Client @client = @G_GetClient( i );
        if ( client.state() < CS_SPAWNED )
            continue;

        if ( !show )
        {
            client.setHUDStat( STAT_PROGRESS_SELF, 0 );
            client.setHUDStat( STAT_PROGRESS_OTHER, 0 );
            continue;
        }

        int myTeam = client.team;
        if ( myTeam != TEAM_ALPHA && myTeam != TEAM_BETA )
            myTeam = TEAM_ALPHA; // spectators see alpha on the left, beta on the right
        int otherTeam = ( myTeam == TEAM_ALPHA ) ? TEAM_BETA : TEAM_ALPHA;

        // positive = drawn in own team color, negative = drawn in enemy color
        client.setHUDStat( STAT_PROGRESS_SELF, PD_Percent( myTeam ) );
        client.setHUDStat( STAT_PROGRESS_OTHER, -PD_Percent( otherTeam ) );
    }
}

// every point of damage a player takes comes off their team HP, overkill included
// (same number the game shows as the damage popup)
void PD_OnDamage( Entity @target, float damage )
{
    if ( !PD_IsPlaying() || @target == null || @target.client == null || target.isGhosting() )
        return;
    if ( target.team != TEAM_ALPHA && target.team != TEAM_BETA )
        return;
    if ( damage <= 0.0f )
        return;

    // warshell (e.g. spawn protection) only lets 25% through, the event reports the unreduced number
    if ( target.client.inventoryCount( POWERUP_SHELL ) > 0 )
        damage *= 0.25f;

    PD_SetTeamHP( target.team, pdTeamHP[target.team] - damage );
}

void PD_CheckKO()
{
    if ( !PD_IsPlaying() )
        return;

    if ( pdTeamHP[TEAM_ALPHA] <= 0.0f || pdTeamHP[TEAM_BETA] <= 0.0f )
    {
        G_CenterPrintMsg( null, "K.O.!" );
        match.launchState( MATCH_STATE_POSTMATCH );
    }
}

///*****************************************************************
/// ARMOR SHARDS (replace ammo pickups)
///*****************************************************************

void PD_shard_touch( Entity @ent, Entity @other, const Vec3 planeNormal, int surfFlags )
{
    if ( @other.client == null || other.isGhosting() || other.health <= 0 )
        return;
    if ( ( gametype.pickableItemsMask & IT_ARMOR ) == 0 )
        return; // countdown / postmatch
    if ( other.client.armor >= PD_SHARD_MAX )
        return;

    float armor = other.client.armor + PD_SHARD_ARMOR;
    if ( armor > PD_SHARD_MAX )
        armor = PD_SHARD_MAX;
    other.client.armor = armor;

    G_Sound( other, CHAN_AUTO, pdShardSound, 1.0f );

    // hide until respawn
    ent.solid = SOLID_NOT;
    ent.svflags |= SVF_NOCLIENT;
    ent.linkEntity();
    ent.nextThink = levelTime + PD_SHARD_RESPAWN;
}

void PD_shard_think( Entity @ent )
{
    ent.solid = SOLID_TRIGGER;
    ent.svflags &= ~SVF_NOCLIENT;
    ent.linkEntity();
    ent.respawnEffect();
}

void PD_SpawnShard( const Vec3 &in origin )
{
    Entity @shard = @G_SpawnEntity( "pd_armor_shard" );
    if ( @shard == null )
        return;
    shard.type = ET_GENERIC;
    shard.modelindex = pdShardModel;
    shard.effects = EF_ROTATE_AND_BOB;
    shard.setSize( Vec3( -16, -16, -16 ), Vec3( 16, 16, 40 ) );
    shard.solid = SOLID_TRIGGER;
    shard.origin = origin;
    shard.svflags &= ~SVF_NOCLIENT;
    @shard.touch = PD_shard_touch;
    @shard.think = PD_shard_think;
    shard.linkEntity();
}

void PD_ReplaceAmmoWithShards()
{
    int replaced = 0;
    for ( int tag = AMMO_GUNBLADE; tag <= AMMO_PACK; tag++ )
    {
        if ( tag >= AMMO_TOTAL && tag < AMMO_PACK_WEAK )
            continue;

        Item @item = @G_GetItem( tag );
        if ( @item == null )
            continue;

        array<Entity @> @ents = G_FindByClassname( item.classname );
        for ( uint i = 0; i < ents.size(); i++ )
        {
            Entity @ammo = @ents[i];
            if ( @ammo.item == null || ( ammo.item.type & IT_AMMO ) == 0 )
                continue;
            Vec3 origin = ammo.origin;
            ammo.freeEntity();
            PD_SpawnShard( origin );
            replaced++;
        }
    }
    G_Print( "Power Duel: replaced " + replaced + " ammo pickups with armor shards\n" );
}

///*****************************************************************
/// LOCAL FUNCTIONS
///*****************************************************************

void PD_GiveAllWeapons( Client @client )
{
    Item @item;
    Item @ammoItem;

    for ( int i = WEAP_GUNBLADE + 1; i < WEAP_TOTAL; i++ )
    {
        if ( i == WEAP_INSTAGUN )
            continue;

        client.inventoryGiveItem( i );

        @item = @G_GetItem( i );

        @ammoItem = @G_GetItem( item.ammoTag );
        if ( @ammoItem != null )
            client.inventorySetCount( ammoItem.tag, ammoItem.inventoryMax );

        @ammoItem = item.weakAmmoTag == AMMO_NONE ? null : @G_GetItem( item.weakAmmoTag );
        if ( @ammoItem != null )
            client.inventorySetCount( ammoItem.tag, ammoItem.inventoryMax );
    }
}

void PD_playerKilled( Entity @target, Entity @attacker, Entity @inflictor )
{
    if ( match.getState() != MATCH_STATE_PLAYTIME )
        return;
    if ( @target.client == null )
        return;

    pdQuadLife[target.playerNum] = false;

    // no weapon drops, no backpacks
    award_playerKilled( @target, @attacker, @inflictor );
}

void PD_SetUpMatch()
{
    int i, j;
    Entity @ent;
    Team @team;

    G_RemoveAllProjectiles();
    gametype.shootingDisabled = false;
    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false; // team score changes every hit, don't spam lead announcements
    gametype.countdownEnabled = true;

    PD_ResetTracking();

    // set team HP *before* respawning players so nobody spawns with last-stand quad
    PD_SetTeamHP( TEAM_ALPHA, PD_TEAM_HP );
    PD_SetTeamHP( TEAM_BETA, PD_TEAM_HP );

    for ( i = TEAM_PLAYERS; i < GS_MAX_TEAMS; i++ )
    {
        @team = @G_GetTeam( i );
        team.stats.clear();

        for ( j = 0; @team.ent( j ) != null; j++ )
        {
            @ent = @team.ent( j );
            ent.client.stats.clear();
            ent.client.respawn( false );
        }
    }

    // stats.clear() above zeroed the scores, write the HP back
    PD_SetTeamHP( TEAM_ALPHA, PD_TEAM_HP );
    PD_SetTeamHP( TEAM_BETA, PD_TEAM_HP );

    G_Items_RespawnByType( IT_ARMOR, 0, 15 );
    G_Items_RespawnByType( IT_HEALTH, HEALTH_MEGA, 15 );
    G_Items_RespawnByType( IT_HEALTH, HEALTH_ULTRA, 15 );
    G_RemoveDeadBodies();

    int soundindex = G_SoundIndex( "sounds/announcer/countdown/fight0" + ( 1 + ( rand() & 1 ) ) );
    G_AnnouncerSound( null, soundindex, GS_MAX_TEAMS, false, null );
    G_CenterPrintMsg( null, "FIGHT!\n" + int( PD_TEAM_HP ) + " team HP each - it never comes back" );
}

///*****************************************************************
/// MODULE SCRIPT CALLS
///*****************************************************************

bool GT_Command( Client @client, const String &cmdString, const String &argsString, int argc )
{
    if ( cmdString == "cvarinfo" )
    {
        GENERIC_CheatVarResponse( client, cmdString, argsString, argc );
        return true;
    }
    else if ( cmdString == "gametype" )
    {
        String response = "";
        Cvar fs_game( "fs_game", "", 0 );
        String manifest = gametype.manifest;

        response += "\n";
        response += "Gametype " + gametype.name + " : " + gametype.title + "\n";
        response += "----------------\n";
        response += "Version: " + gametype.version + "\n";
        response += "Author: " + gametype.author + "\n";
        response += "Mod: " + fs_game.string + ( !manifest.empty() ? " (manifest: " + manifest + ")" : "" ) + "\n";
        response += "----------------\n";

        G_PrintMsg( client.getEnt(), response );
        return true;
    }

    return false;
}

bool GT_UpdateBotStatus( Entity @ent )
{
    return GENERIC_UpdateBotStatus( ent );
}

Entity @GT_SelectSpawnPoint( Entity @self )
{
    return GENERIC_SelectBestRandomSpawnPoint( self, "info_player_deathmatch" );
}

String @GT_ScoreboardMessage( uint maxlen )
{
    String scoreboardMessage = "";
    String entry;
    Team @team;
    Entity @ent;
    int i, t;

    for ( t = TEAM_ALPHA; t < GS_MAX_TEAMS; t++ )
    {
        @team = @G_GetTeam( t );

        entry = "&t " + t + " " + team.stats.score + " " + team.ping + " ";
        if ( scoreboardMessage.len() + entry.len() < maxlen )
            scoreboardMessage += entry;

        for ( i = 0; @team.ent( i ) != null; i++ )
        {
            @ent = @team.ent( i );

            int playerID = ( ent.isGhosting() && ( match.getState() == MATCH_STATE_PLAYTIME ) ) ? -( ent.playerNum + 1 ) : ent.playerNum;

            // "AVATAR Name Clan HP Frags Ping R"
            entry = "&p " + playerID + " " + playerID + " "
                    + ent.client.clanName + " "
                    + ent.client.stats.score + " "
                    + ent.client.stats.frags + " "
                    + ent.client.ping + " "
                    + ( ent.client.isReady() ? "1" : "0" ) + " ";

            if ( scoreboardMessage.len() + entry.len() < maxlen )
                scoreboardMessage += entry;
        }
    }

    return scoreboardMessage;
}

void GT_ScoreEvent( Client @client, const String &score_event, const String &args )
{
    if ( score_event == "dmg" )
    {
        // args: target entnum, damage, attacker entnum
        PD_OnDamage( G_GetEntity( args.getToken( 0 ).toInt() ), args.getToken( 1 ).toFloat() );
    }
    else if ( score_event == "kill" )
    {
        Entity @attacker = null;

        if ( @client != null )
            @attacker = @client.getEnt();

        int arg1 = args.getToken( 0 ).toInt();
        int arg2 = args.getToken( 1 ).toInt();

        PD_playerKilled( G_GetEntity( arg1 ), attacker, G_GetEntity( arg2 ) );
    }
}

void GT_PlayerRespawn( Entity @ent, int old_team, int new_team )
{
    if ( ent.isGhosting() )
        return;

    if ( gametype.isInstagib )
    {
        ent.client.inventoryGiveItem( WEAP_INSTAGUN );
        ent.client.inventorySetCount( AMMO_INSTAS, 1 );
        ent.client.inventorySetCount( AMMO_WEAK_INSTAS, 1 );
    }
    else
    {
        ent.client.inventorySetCount( WEAP_GUNBLADE, 1 );
        ent.client.inventorySetCount( AMMO_GUNBLADE, 1 );

        // full attack: every weapon, always
        PD_GiveAllWeapons( ent.client );

        if ( match.getState() <= MATCH_STATE_WARMUP )
        {
            ent.client.inventoryGiveItem( ARMOR_YA );
            ent.client.inventoryGiveItem( ARMOR_YA );
        }
    }

    // low on team HP: this life gets quad
    pdQuadLife[ent.playerNum] = false;
    if ( PD_IsPlaying() && ( new_team == TEAM_ALPHA || new_team == TEAM_BETA ) && pdTeamHP[new_team] <= PD_QUAD_HP )
    {
        pdQuadLife[ent.playerNum] = true;
        ent.client.inventorySetCount( POWERUP_QUAD, PD_QUAD_REFILL );
        G_CenterPrintMsg( ent, "LAST STAND - QUAD DAMAGE!" );
    }

    if ( ent.client.canSelectWeapon( WEAP_ROCKETLAUNCHER ) )
        ent.client.selectWeapon( WEAP_ROCKETLAUNCHER );
    else
        ent.client.selectWeapon( -1 );

    ent.respawnEffect();
}

void GT_ThinkRules()
{
    if ( match.scoreLimitHit() || match.timeLimitHit() || match.suddenDeathFinished() )
    {
        if ( !match.checkExtendPlayTime() )
            match.launchState( match.getState() + 1 );
    }

    GENERIC_Think();

    if ( match.getState() >= MATCH_STATE_POSTMATCH )
    {
        PD_UpdateHUD();
        return;
    }

    PD_CheckKO();

    for ( int i = 0; i < maxClients; i++ )
    {
        Entity @ent = @G_GetClient( i ).getEnt();
        if ( ent.client.state() >= CS_SPAWNED && ent.team != TEAM_SPECTATOR )
        {
            if ( ent.health > ent.maxHealth )
            {
                ent.health -= ( frameTime * 0.001f );
                if ( ent.health < ent.maxHealth )
                    ent.health = ent.maxHealth;
            }

            if ( pdQuadLife[i] && !ent.isGhosting() && ent.health > 0
                    && ent.client.inventoryCount( POWERUP_QUAD ) < PD_QUAD_REFILL )
                ent.client.inventorySetCount( POWERUP_QUAD, PD_QUAD_REFILL );
        }
    }

    PD_UpdateHUD();
}

bool GT_MatchStateFinished( int incomingMatchState )
{
    if ( match.getState() <= MATCH_STATE_WARMUP && incomingMatchState > MATCH_STATE_WARMUP
            && incomingMatchState < MATCH_STATE_POSTMATCH )
        match.startAutorecord();

    if ( match.getState() == MATCH_STATE_POSTMATCH )
        match.stopAutorecord();

    return true;
}

void GT_MatchStateStarted()
{
    switch ( match.getState() )
    {
    case MATCH_STATE_WARMUP:
        gametype.pickableItemsMask = gametype.spawnableItemsMask;
        gametype.dropableItemsMask = 0;
        GENERIC_SetUpWarmup();
        SpawnIndicators::Create( "info_player_deathmatch", TEAM_BETA );
        SpawnIndicators::Create( "info_player_start", TEAM_BETA );
        break;

    case MATCH_STATE_COUNTDOWN:
        gametype.pickableItemsMask = 0;
        gametype.dropableItemsMask = 0;
        GENERIC_SetUpCountdown();
        SpawnIndicators::Delete();
        break;

    case MATCH_STATE_PLAYTIME:
        gametype.pickableItemsMask = gametype.spawnableItemsMask;
        gametype.dropableItemsMask = 0;
        PD_SetUpMatch();
        break;

    case MATCH_STATE_POSTMATCH:
        gametype.pickableItemsMask = 0;
        gametype.dropableItemsMask = 0;
        GENERIC_SetUpEndMatch();
        break;

    default:
        break;
    }
}

void GT_Shutdown()
{
}

void GT_SpawnGametype()
{
    PD_ResetTracking();
    PD_ReplaceAmmoWithShards();
}

void GT_InitGametype()
{
    gametype.title = "Power Duel";
    gametype.version = "1.0";
    gametype.author = "cocainediesel.fun / goochie (based on Warfork Duel)";

    if ( !G_FileExists( "configs/server/gametypes/" + gametype.name + ".cfg" ) )
    {
        String config;

        config = "// '" + gametype.title + "' gametype configuration file\n"
                 + "// This config will be executed each time the gametype is started\n"
                 + "\n\n// map rotation\n"
                 + "set g_maplist \"\" // list of maps in automatic rotation\n"
                 + "set g_maprotation \"0\"   // 0 = same map, 1 = in order, 2 = random\n"
                 + "\n// game settings\n"
                 + "set g_scorelimit \"0\" // team HP decides the match, leave this at 0\n"
                 + "set g_timelimit \"10\"\n"
                 + "set g_warmup_timelimit \"3\"\n"
                 + "set g_match_extendedtime \"2\"\n"
                 + "set g_allow_falldamage \"1\"\n"
                 + "set g_allow_selfdamage \"1\"\n"
                 + "set g_allow_teamdamage \"0\"\n"
                 + "set g_allow_stun \"1\"\n"
                 + "set g_teams_maxplayers \"1\"\n"
                 + "set g_teams_allow_uneven \"0\"\n"
                 + "set g_countdown_time \"5\"\n"
                 + "set g_maxtimeouts \"-1\" // -1 = unlimited\n"
                 + "\necho \"" + gametype.name + ".cfg executed\"\n";

        G_WriteFile( "configs/server/gametypes/" + gametype.name + ".cfg", config );
        G_Print( "Created default config file for '" + gametype.name + "'\n" );
        G_CmdExecute( "exec configs/server/gametypes/" + gametype.name + ".cfg silent" );
    }

    // ammo must spawn so GT_SpawnGametype can find its spots and swap them for shards;
    // weapons are left out since everyone already has all of them
    gametype.spawnableItemsMask = ( IT_AMMO | IT_ARMOR | IT_HEALTH );
    if ( gametype.isInstagib )
        gametype.spawnableItemsMask &= ~uint( G_INSTAGIB_NEGATE_ITEMMASK );

    gametype.respawnableItemsMask = gametype.spawnableItemsMask;
    gametype.dropableItemsMask = 0; // no weapon drops, no backpacks
    gametype.pickableItemsMask = gametype.spawnableItemsMask;

    gametype.isTeamBased = true;
    gametype.isRace = false;
    gametype.hasChallengersQueue = true;
    gametype.maxPlayersPerTeam = 1;

    gametype.ammoRespawn = 20;
    gametype.armorRespawn = 25;
    gametype.weaponRespawn = 10;
    gametype.healthRespawn = 25;
    gametype.powerupRespawn = 90;
    gametype.megahealthRespawn = 20;
    gametype.ultrahealthRespawn = 40;

    gametype.readyAnnouncementEnabled = false;
    gametype.scoreAnnouncementEnabled = false;
    gametype.countdownEnabled = false;
    gametype.mathAbortDisabled = false;
    gametype.shootingDisabled = false;
    gametype.infiniteAmmo = true;
    gametype.canForceModels = true;
    gametype.canShowMinimap = false;
    gametype.teamOnlyMinimap = false;

    gametype.mmCompatible = false;

    gametype.spawnpointRadius = 64;
    if ( gametype.isInstagib )
        gametype.spawnpointRadius *= 2;

    for ( int team = TEAM_PLAYERS; team < GS_MAX_TEAMS; team++ )
        gametype.setTeamSpawnsystem( team, SPAWNSYSTEM_INSTANT, 0, 0, false );

    G_ConfigString( CS_SCB_PLAYERTAB_LAYOUT, "%a l1 %n 112 %s 52 %i 52 %i 42 %l 38 %r l1" );
    G_ConfigString( CS_SCB_PLAYERTAB_TITLES, "AVATAR Name Clan HP Frags Ping R" );

    pdShardSound = G_SoundIndex( "sounds/items/armor_shard" );
    pdShardModel = G_ModelIndex( "models/items/armor/shard/shard.md3" );

    G_RegisterCommand( "gametype" );

    G_Print( "Gametype '" + gametype.title + "' initialized\n" );
}
