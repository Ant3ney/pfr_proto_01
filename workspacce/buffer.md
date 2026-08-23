<!-- AI Agents should not read this file -->

I want to begin the interaction interface on this project. It does not have to do anything right now. Just make the interface and in in sublicant chats, I'll have you do things with it.
Do the same for the NPC NPC Behavior Script. Make a parrent class for that. Make it so that the NPC controller has a property where you can pass in a script that is a child of NPC behavior script. 


› Good. Now Build a child of the NPC behavior sccript called TrainerBehavior. Sure that the behavior script accesses the NPC controller and the PFR Chharacter class


O yeah, I forgot there already is a NPC behavior class. Good. Update trainer behavir so that after moving to the target locaiton by the player, it stops moving. Also, I notice that the NPC will want to keep moving to the actual loction of the player even though the player already ocupies that space. Causing the NPC to do weird things. The target spot should be beside the player. The target spot should be calcualted by, the vector from the NPC to the player direction. Follow that direction untill you get to the player location minus the bounding box radius of the player, minus a buffer offset. I'm providing a rough calculation here but it's up to you to ensure the NPC stops besides the player. Ensure the NPC stops folloing the player if it reaches the player target.




Make a new class in core called GameInstance. It controlls global things about the game. Add a function you can pass in true or false. It will preventt the player from being able to move if false. It will allow the player to move if true. Then make it so that on trainer detection of the player, the player can't move anymore
