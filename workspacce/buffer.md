<!-- AI Agents should not read this file -->

I want to begin the interaction interface on this project. It does not have to do anything right now. Just make the interface and in in sublicant chats, I'll have you do things with it.
Do the same for the NPC NPC Behavior Script. Make a parrent class for that. Make it so that the NPC controller has a property where you can pass in a script that is a child of NPC behavior script. 


› Good. Now Build a child of the NPC behavior sccript called TrainerBehavior. Sure that the behavior script accesses the NPC controller and the PFR Chharacter class


O yeah, I forgot there already is a NPC behavior class. Good. Update trainer behavir so that after moving to the target locaiton by the player, it stops moving. Also, I notice that the NPC will want to keep moving to the actual loction of the player even though the player already ocupies that space. Causing the NPC to do weird things. The target spot should be beside the player. The target spot should be calcualted by, the vector from the NPC to the player direction. Follow that direction untill you get to the player location minus the bounding box radius of the player, minus a buffer offset. I'm providing a rough calculation here but it's up to you to ensure the NPC stops besides the player. Ensure the NPC stops folloing the player if it reaches the player target.




Make a new class in core called GameInstance. It controlls global things about the game. Add a function you can pass in true or false. It will preventt the player from being able to move if false. It will allow the player to move if true. Then make it so that on trainer detection of the player, the player can't move anymore





Lets build a basic dialog system. As you know, the UI works via calling the template class to display a UI template, you then get back an object that controlls that template. Dialog is simple, the caller that opened up the dialog template controlls the dialog system. Right now we are working on the trainer dialog. Yes, make it so that when a trainer reaches it's location target, it opens the dialog menu and dialog starts. In a Trainer character, ensure if trainer is selected, you can also pass in a dialog object. The dialog object has the character name and an array of strings that is what gets displayed to the dialog UI.




See this poject. This is the project came before this. It has lots of issues but one thing it does right is it's battle system. I want you to make a battle sccene in this project. To look just like how it does in that project. Don't port / import the UI. That is already in this project. Import the actual 3D scene and the camera and the spawn placements. Dont import scrips and logic. We are going to take this slowly. For now, just give me the scene and it's art.


