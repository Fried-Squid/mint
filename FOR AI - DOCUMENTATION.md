-- Pulling events
while true do
  os.pullEvent("turtle_inventory")
  print("The inventory was changed.")
end

-- everything ever
Globals

    _G
    colors
    colours
    commands
    disk
    fs
    gps
    help
    http
    io
    keys
    multishell
    os
    paintutils
    parallel
    peripheral
    pocket
    rednet
    redstone
    settings
    shell
    term
    textutils
    turtle
    vector
    window

Modules

    cc.audio.dfpwm
    cc.completion
    cc.expect
    cc.image.nft
    cc.pretty
    cc.require
    cc.shell.completion
    cc.strings

Peripherals

    command
    computer
    drive
    modem
    monitor
    printer
    redstone_relay
    speaker

Generic Peripherals

    energy_storage
    fluid_storage
    inventory -- ignore this these arent real types theyre weird

Events

    alarm
    char
    computer_command
    disk
    disk_eject
    file_transfer
    http_check
    http_failure
    http_success
    key
    key_up
    modem_message
    monitor_resize
    monitor_touch
    mouse_click
    mouse_drag
    mouse_scroll
    mouse_up
    paste
    peripheral
    peripheral_detach
    rednet_message
    redstone
    speaker_audio_empty
    task_complete
    term_resize
    terminate
    timer
    turtle_inventory
    websocket_closed
    websocket_failure
    websocket_message
    websocket_success

-- os doc

pullEvent([filter])	Pause execution of the current thread and waits for any events matching filter.
pullEventRaw([filter])	Pause execution of the current thread and waits for events, including the terminate event.
sleep(time)	Pauses execution for the specified number of seconds, alias of _G.sleep.
version()	Get the current CraftOS version (for example, CraftOS 1.9).
run(env, path, ...)	Run the program at the given path with the specified environment and arguments.
queueEvent(name, ...)	Adds an event to the event queue.
startTimer(time)	Starts a timer that will run for the specified number of seconds.
cancelTimer(token)	Cancels a timer previously started with startTimer.
setAlarm(time)	Sets an alarm that will fire at the specified in-game time.
cancelAlarm(token)	Cancels an alarm previously started with setAlarm.
shutdown()	Shuts down the computer immediately.
reboot()	Reboots the computer immediately.
getComputerID()	Returns the ID of the computer.
computerID()	Returns the ID of the computer.
getComputerLabel()	Returns the label of the computer, or nil if none is set.
computerLabel()	Returns the label of the computer, or nil if none is set.
setComputerLabel([label])	Set the label of this computer.
clock()	Returns the number of seconds that the computer has been running.
time([locale])	Returns the current time depending on the string passed in.
day([args])	Returns the day depending on the locale specified.
epoch([args])	Returns the number of milliseconds since an epoch depending on the locale.
date([format [, time]])	Returns a date string (or table) using a specified format string and optional time to format.

-- turtle

craft([limit=64])	Craft a recipe based on the turtle's inventory.
native	The builtin turtle API, without any generated helper functions.
forward()	Move the turtle forward one block.
back()	Move the turtle backwards one block.
up()	Move the turtle up one block.
down()	Move the turtle down one block.
turnLeft()	Rotate the turtle 90 degrees to the left.
turnRight()	Rotate the turtle 90 degrees to the right.
dig([side])	Attempt to break the block in front of the turtle.
digUp([side])	Attempt to break the block above the turtle.
digDown([side])	Attempt to break the block below the turtle.
place([text])	Place a block or item into the world in front of the turtle.
placeUp([text])	Place a block or item into the world above the turtle.
placeDown([text])	Place a block or item into the world below the turtle.
drop([count])	Drop the currently selected stack into the inventory in front of the turtle, or as an item into the world if there is no inventory.
dropUp([count])	Drop the currently selected stack into the inventory above the turtle, or as an item into the world if there is no inventory.
dropDown([count])	Drop the currently selected stack into the inventory below the turtle, or as an item into the world if there is no inventory.
select(slot)	Change the currently selected slot.
getItemCount([slot])	Get the number of items in the given slot.
getItemSpace([slot])	Get the remaining number of items which may be stored in this stack.
detect()	Check if there is a solid block in front of the turtle.
detectUp()	Check if there is a solid block above the turtle.
detectDown()	Check if there is a solid block below the turtle.
compare()	Check if the block in front of the turtle is equal to the item in the currently selected slot.
compareUp()	Check if the block above the turtle is equal to the item in the currently selected slot.
compareDown()	Check if the block below the turtle is equal to the item in the currently selected slot.
attack([side])	Attack the entity in front of the turtle.
attackUp([side])	Attack the entity above the turtle.
attackDown([side])	Attack the entity below the turtle.
suck([count])	Suck an item from the inventory in front of the turtle, or from an item floating in the world.
suckUp([count])	Suck an item from the inventory above the turtle, or from an item floating in the world.
suckDown([count])	Suck an item from the inventory below the turtle, or from an item floating in the world.
getFuelLevel()	Get the maximum amount of fuel this turtle currently holds.
refuel([count])	Refuel this turtle.
compareTo(slot)	Compare the item in the currently selected slot to the item in another slot.
transferTo(slot [, count])	Move an item from the selected slot to another one.
getSelectedSlot()	Get the currently selected slot.
getFuelLimit()	Get the maximum amount of fuel this turtle can hold.
equipLeft()	Equip (or unequip) an item on the left side of this turtle.
equipRight()	Equip (or unequip) an item on the right side of this turtle.
getEquippedLeft()	Get the upgrade currently equipped on the left of the turtle.
getEquippedRight()	Get the upgrade currently equipped on the right of the turtle.
inspect()	Get information about the block in front of the turtle.
inspectUp()	Get information about the block above the turtle.
inspectDown()	Get information about the block below the turtle.
getItemDetail([slot [, detailed]])	Get detailed information about the items in the given slot.
