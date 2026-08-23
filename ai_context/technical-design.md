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

## GameIstance and game mode

The game instance will be omipresent and will be what changes levels and what displays the UI.

## Creature System

The showdown project has all the pokemon stat data. It's best to use that for defining data about each creature. In this project, it is to be an API wrapper. You pass in an id and get what every data you need about that spcific pokemon ID

## Collection system

This is the management of the players stats about there pokemon. For now, we will just save the xp level and the lv of the pokemon

We will also save the collection of the player. Apecific pokemon collected instance is called a `pcl` or pokemon collection instance. 

The object of a pcl is 

```
{
  pokemonId: 'picashu',
  pclID: 'j34jd98wej',
  party: {
    inParty: true
    slot: '3'
  },
  instanceStats: {
    health: '40%',
    xp: '30%'
  }
}
```

### An example use of the Collection System

Battle start --> Get slot number from party --> query pcl obj from collection via slot number of party --> pcl obj --> Run battle, pass in stats

## Progression System

Progression is a large object with a lot of methods. You passin in input and it returns a out put. Ususaly a boolean. For example, if a man blocks a path and he will move if you talk to him, you call the progression system api method and it will access DB and save data. From there, it will know that you don't have enough badges and will return false. The overwolrd interaction system will then make the character stay put.

## Save system.

This is a large, organized object. Aupon starting your game, the data loads. The systems load from temp save data and will call the tempSaveData function a lot to pass in all saveable data to the tempSave data obj. When the user presses save game, the real save data becomes the temp save data.
