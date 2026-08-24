# Technical Design

## Battle System

Black box that talks to a modified pokemon server project. That project facilitates the whole battle system. This game gives hooks, callbacks, and reacts to the events of the pokemon showdown server

## Overworld and traversal.

Simple character controller. The art of the overworld will be made with modular assets that way the world can be easily made. For the time being, no additional tools will be implimentedt to speed up overwold creation. The overwold will be developed via simple drag and drop placements of the assets.

Each zone will have NPC's and objects that take in interation scrips. They will also take in location scrips. Aupon init of that zone when the player enters that zone, the location scripts will read the progression api and move the NPCs to where they need to go.

The interaction scrip, being a child of a interaction parrent, will be a free handed way of handling what happons when interacted and when an interaction is called. The interaction parrent provides an ocean of healpers to help facilitate this.


### Character

Can be a player or NPC. Takes a input represented as the player controller component or  a NPC controller that decides what it does and where it goes.

### Controllers

### Battle being

To start a battle, you call a function on the game instance class. You pass in the data needed to pas into the battle there. Some data is implicit and you don't' have to pass it in. This function on the game istnace is called startBattle(...). It also handles the visual changes needed to start the battle intor sequence. Saves data to temportal properties that the battle scene will use to set up the battle.

#### NPCController

Specify a point on the map and the NPC will use it's  npc controller to manage the logic to go there.

Can spcifify and make logic saying that this is the kind of character that sits in one spot and looks forward untill the player enters in front of him and then runs to the player and starts a battle.

#### NPC Behavior Script

This is a type script that you can pas int the NPC cotroller and it will controll what the NPC does. The NPC controller simply provides a large ammount of helper functions the NPC behavior can call on for help.

#### Player controller

The implimentation of how the player input controlls the player. Additionaly, somethings the controll of the player may also be controlled by the game and not the player. TLypicaly, during a sequence.

### Interaction

Entities that impliment this interface will be have access to a lot of objects with moethods need to drive the interaction along.

### Sequences

A sequnce can be started via all kinds of things not limeted to an interaction or an event. A sequence, on start, will gather all of it's actors needed for the seqence. A entity needed for a sequence is called an actor. The sequence is simply the name of all the interactions and behavior used to make a squence. It's nothing really set in code. It just describes a set of interelated code.

## GameInstance and game mode

The implemented `GameInstance` autoload owns cross-scene gameplay state. It
currently exposes the player-movement enable flag used by sequences and dialog
callers.

## UI Template System

The implemented `UIManager` autoload displays the shared UI template and
returns the live `UITemplate` instance to its caller. The caller owns content,
callbacks, advancement, gameplay locks, and cleanup; `UIManager` does not own a
dialog state machine or prevent overlapping templates. Use `UITemplate.close()`
to run dismissal cleanup before the instance is freed.

See the [UI Template System guide](../core/ui/README.md) for the complete API,
copyable message, confirmation, and multi-line dialog recipes, editor setup,
styling, lifecycle rules, and troubleshooting.

## Creature System

The implemented Creature System is the `CreatureSystem` autoload backed by the local data snapshot in `data/creatures/`. `CreatureSystem.get_creature(pokemon_id)` is the canonical API; `get_pokemon(pokemon_id)` is an alias. A successful lookup returns the complete PokeAPI `pokemon` record at the root, plus its location encounters in `encounters_data` and complete `pokemon-species` and `evolution-chain` records under `species_data` and `evolution_chain_data`. It performs no network request.

The snapshot contains 1,351 Pokemon records: 1,025 default National-Dex entries and 326 alternate or battle forms. Numeric IDs are PokeAPI Pokemon IDs, so default forms use National-Dex IDs `1` through `1025`, while alternate forms use PokeAPI's higher IDs such as `10001`. Call `has_pokemon(id)` before optional lookups when appropriate. Unknown IDs return an empty dictionary and set `get_last_error()`.

Records are losslessly gzip-compressed and loaded lazily. The runtime keeps a bounded cache and returns deep copies so consumers cannot mutate cached source data. Source provenance and counts are in `data/creatures/manifest.json`; the deterministic sync and full integrity check are provided by `tools/sync_pokeapi_data.py`. The JSON retains PokeAPI's sprite and cry URLs, but those binary media assets are not part of the local stat-data snapshot.

## Collection system

The implemented `CollectionSystem` autoload owns the player's captured Pokemon and six-slot party. A specific captured instance is called a `pcl` (Pokemon collection instance). Pokemon IDs are the numeric PokeAPI IDs accepted by `CreatureSystem`; every PCL has a separately generated unique instance ID.

On a fresh runtime, the collection starts with a full level-3 party in this slot order: Palkia, Mothim, Hoothoot, Vespiquen, Luxray, and Pelipper. Each starts at full health and zero XP progress. Loading collection save data replaces this starting collection.

The canonical PCL object is:

```
{
  pokemonId: 25,
  pclID: "generated-unique-instance-id",
  party: {
    inParty: true,
    slot: 3
  },
  instanceStats: {
    health: 0.4,
    xp: 0.3,
    level: 5
  }
}
```

Party slots are integers from `1` through `6`. A Pokemon outside the party has `inParty: false` and `slot: null`. Health and XP are normalized percentages from `0.0` through `1.0`; level is an integer from `1` through `100`.

`add_pokemon(...)` creates a PCL, `get_pcl(pcl_id)` queries a captured instance, and `get_pcl_by_party_slot(slot)` implements the battle lookup described below. `set_party_slot(...)` rejects an occupied destination instead of silently removing another Pokemon. `update_instance_stats(...)` atomically applies any subset of health, XP, and level. All returned objects are deep copies.

`get_save_data()` returns the full collection in capture/import order. `load_save_data(...)` validates Pokemon IDs, PCL IDs, stats, and unique party slots before replacing any current data, so an invalid save cannot partially overwrite the active collection.

### An example use of the Collection System

Battle start --> Get slot number from party --> query pcl obj from collection via slot number of party --> pcl obj --> Run battle, pass in stats

## Progression System

Progression is a large object with a lot of methods. You passin in input and it returns a out put. Ususaly a boolean. For example, if a man blocks a path and he will move if you talk to him, you call the progression system api method and it will access DB and save data. From there, it will know that you don't have enough badges and will return false. The overwolrd interaction system will then make the character stay put.

## Save system.

This is a large, organized object. Aupon starting your game, the data loads. The systems load from temp save data and will call the tempSaveData function a lot to pass in all saveable data to the tempSave data obj. When the user presses save game, the real save data becomes the temp save data.
