#####################################################################
#
# CSCB58 Winter 2025 Assembly Final Project
# University of Toronto, Scarborough
#
# Student: Jeremy Itsuki Chong
#
# Bitmap Display Configuration:
# - Unit width in pixels: 4 (update this as needed)
# - Unit height in pixels: 4 (update this as needed)
# - Display width in pixels: 256 (update this as needed)
# - Display height in pixels: 256 (update this as needed)
# - Base Address for Display: 0x10008000 ($gp)
#
# Which milestoneshave been reached in this submission?
# (See the assignment handout for descriptions of the milestones)
# - Milestone 4 (all)
#
# Which approved features have been implemented for milestone 4?
# (See the assignment handout for the list of additional features)
# 1. Moving platforms
# 2. Moving objects
# 3. Double jump
# 4. Start menu
#
# Link to video demonstration for final submission:
# - https://youtu.be/vSMBMO7GK7o
#
# Are you OK with us sharing the video with people outside course staff?
# - yes
#
# Any additional information that the TA needs to know:
# N/A
#
#####################################################################

# Base addresses for game setup
.eqv DISPLAY_ADDRESS 0x10008000
.eqv KEYBOARD_ADDRESS 0xffff0000

# Colours
.eqv GREY 0x808080
.eqv BLACK 0x000000
.eqv RED 0xff0000
.eqv GREEN 0xaaff00
.eqv BACKGROUND_COLOUR 0xede8d0
.eqv PLATFORM_COLOUR 0x964b00
.eqv YELLOW 0xffbf00
.eqv DARK_YELLOW 0xe49b0f
.eqv HOLE_COLOUR 0xdaa520
.eqv LIGHT_BLUE 0xd1e5f4
.eqv LIGHT_GREY 0xd3d3d3

# Game constants
.eqv DELAY 50
.eqv PLAYER_MOVEMENT_UP -11
.eqv PLAYER_MOVEMENT_LEFT -8
.eqv PLAYER_MOVEMENT_DOWN 1
.eqv PLAYER_MOVEMENT_RIGHT 8

# Game data
.data
padding: .space 36000 # padding since data gets messed up on reset

platform1: .word 208, 255, 12 # start x, end x, y
platform2: .word 60, 160, 40
platform3: .word 72, 156, 25, 1 # start x, end x, y, moving direction

heart1: .word 14088 # 256 * 55 + x-pos
heart2: .word 14120
heart3: .word 14152

cheese: .word 228, 8

cat1: .word 68, 35, 1 # x, y, moving direction
cat2: .word 208, 46

# -------- GAME NOTES --------
# player is 7 x 6 framebuffer units big
# cat is 8 x 5 framebuffer units big
# cheese is 5 x 4 framebuffer units big
# --------------------------------

# -------- REGISTER NOTES --------
# $s0, $s1 represent the player's current x, y position
# $s2 will hold the player's current health
# $s3 holds the number of jumps available for the player (for double jump)
# $s6 holds the cursor position (either 0 or 1) for the start of the game
# $s7 will hold $ra whenever I need to save it and I want to avoid the stack
# --------------------------------

.text
.globl main

main:
	li $a0, BACKGROUND_COLOUR
	jal clear_screen
	jal draw_start_screen
	
init_game:
	# init player's position and other variables
	li $s0, 0
	li $s1, 45
	li $s2, 3
	li $s3, 2
	
	# init game background
	li $a0, BLACK
	jal clear_screen
	jal draw_game_background
	jal draw_hearts
	# init cheese position
	la $t2, cheese
	lw $a0, 0($t2) # load cheese's x pos
	lw $a1, 4($t2) # load cheese's y pos
	jal draw_cheese
	# draw other game objects
	jal draw_all_cats
	jal draw_all_platforms
	j game_loop

game_loop:
	jal draw_player
	jal gravity
	jal move_cat
	jal move_platform

	check_game_input:
		li $t9, KEYBOARD_ADDRESS # init the keyboard
		lw $t8, 0($t9) # load contents of new keypress
		beq $t8, 1, keypress_happened # check if a key was pressed
	
	#sleep 
	li $v0, 32 
	li $a0, DELAY
	syscall
	
	j game_loop
	
# END MAIN PROGRAM
end_main:
	li $v0, 10
	syscall
	
# -------- KEY PRESS FUNCTIONS --------
keypress_happened:
	lw $t2, 4($t9) # load which key was pressed
	
	beq $t2, 0x77, w_pressed
	beq $t2, 0x61, a_pressed
	beq $t2, 0x73, s_pressed
	beq $t2, 0x64, d_pressed
	beq $t2, 0x71, q_pressed
	beq $t2, 0x72, r_pressed
	
	j game_loop

w_pressed: # move character up
	beq $s3, $zero, game_loop # make sure jump count is not zero
	
	jal check_collision_bounds_up
	jal check_collision_platforms_up
	jal clear_player
	addi $s1, $s1, PLAYER_MOVEMENT_UP # move player up 
	addi $s3, $s3, -1
	jal draw_player
	j game_loop

a_pressed: # move character left
	jal check_collision_bounds_left
	jal check_collision_platforms_left
	jal check_collision_cat_left
	jal check_collision_cheese_left
	jal clear_player
	addi $s0, $s0, PLAYER_MOVEMENT_LEFT # move player left
	jal draw_player
	j game_loop

s_pressed: #move character down
	la $a1, game_loop
	jal check_collision_bounds_down
	jal check_collision_platforms_down
	jal check_collision_cat_down
	jal clear_player
	addi $s1, $s1, PLAYER_MOVEMENT_DOWN
	jal draw_player
	j game_loop

d_pressed: # move character right
	jal check_collision_bounds_right
	jal check_collision_platforms_right
	jal check_collision_cat_right
	jal check_collision_cheese_right
	jal clear_player
	addi $s0, $s0, PLAYER_MOVEMENT_RIGHT # move player 1 unit to the right
	jal draw_player
	j game_loop

r_pressed: # restart the game
	j init_game

q_pressed: # quit the game
	j end_main
	
# -------- GAME LOGIC (I.E PHYSICS) FUNCTIONS --------
jump_to_arg1:
	li $s3, 2 # reset jump count if collision
	jr $a1

check_collision_bounds_up:
	addi $t1, $s1, PLAYER_MOVEMENT_UP # calculate next y-position
	bltz $t1, game_loop # if invalid move back to game loop
	jr $ra

check_collision_bounds_left:
	addi $t0, $s0, PLAYER_MOVEMENT_LEFT # calculate next x-position
	bltz $t0, game_loop
	jr $ra

check_collision_bounds_down: # $a1 stores the address to jump to if there  is a collision
	addi $t1, $s1, 6 # calculate player's feet
	addi $t1, $t1, PLAYER_MOVEMENT_DOWN
	bgt $t1, 51, jump_to_arg1 # if there was a collision
	jr $ra

check_collision_bounds_right:
	addi $t0, $s0, 24 # calculate player's right side
	addi $t0, $t0, PLAYER_MOVEMENT_RIGHT # calculate next x-pos
	bge $t0, 256, game_loop
	jr $ra
	
no_collision:
	jr $ra
	
check_collision_single_platform_horizontal: # $a0 stores platform address, $a1 stores next movement position
	add $t0, $s0, $a1 # calculate new position
	addi $t1, $t0, 24 # get player's right side
	
	move $t2, $s1 # player's start y
	addi $t3, $t2, 6 # player's feet

	lw $t4, 0($a0) # start of platform x
	lw $t5, 4($a0) # end of platform x
	lw $t6, 8($a0) # platform y
	
	# check if platform start x is less than player's right side x
	blt $t1, $t4, no_collision
	bgt $t0, $t5, no_collision
	
	# check if player start y <= platform y <= player end y
	blt $t6, $t2, no_collision
	bge $t6, $t3, no_collision
	
	# move player above platform
	jal clear_player
	addi $s1, $t6, -12
	j game_loop
	
check_collision_single_platform_up: # $a0 holds the address of the platform
	move $t0, $s0 # player's start x
	addi $t1, $t0, 24 # get player's right side
	
	move $t2, $s1 # player's start y
	addi $t2, $t2, PLAYER_MOVEMENT_UP # calculate new position
	addi $t3, $t2, 6 # player's feet

	lw $t4, 0($a0) # start of platform x
	lw $t5, 4($a0) # end of platform x
	lw $t6, 8($a0) # platform y
	
	# check if platform start x <= player's x <= platform end x
	blt $t1, $t4, no_collision
	bgt $t0, $t5, no_collision
	
	# check if player start y <= platform y <= player end y
	blt $t6, $t2, no_collision
	bgt $t6, $t3, no_collision
	
	j game_loop

check_collision_platforms_up:
	move $s7, $ra # save $ra
	
	# check if start of platform x <= player's x <= end of platform x
	la $a0, platform1
	jal check_collision_single_platform_up
	
	la $a0, platform2
	jal check_collision_single_platform_up
	
	la $a0, platform3
	jal check_collision_single_platform_up
	
	move $ra, $s7 # restore $ra
	jr $ra

check_collision_platforms_left:
	move $s7, $ra # save $ra
	
	# check if start of platform x <= player's x <= end of platform x
	la $a0, platform1
	li $a1, PLAYER_MOVEMENT_LEFT
	jal check_collision_single_platform_horizontal
	
	la $a0, platform2
	jal check_collision_single_platform_horizontal
	
	la $a0, platform3
	jal check_collision_single_platform_horizontal
	
	move $ra, $s7 # restore $ra
	jr $ra

check_collision_single_platform_down: # $a1 stores the address to jump to if there is a collision
	addi $t0, $s0, 24 # get player's right side
	
	addi $t1, $s1, 6 # player's feet

	lw $t2, 0($a0) # start of platform x
	lw $t3, 4($a0) # end of platform x
	lw $t4, 8($a0) # platform y
	
	# check if platform start x <= player's x <= platform end x
	blt $t0, $t2, no_collision
	bgt $s0, $t3, no_collision
	
	# check if player start y <= platform y <= player end y
	blt $t4, $s1, no_collision
	bgt $t4, $t1, no_collision
	
	li $s3, 2
	
	jr $a1

check_collision_platforms_down: # $a1 will hold the address to jump to if collision
	move $s7, $ra # save $ra
	
	# check if start of platform x <= player's x <= end of platform x
	la $a0, platform1
	jal check_collision_single_platform_down
	
	la $a0, platform2
	jal check_collision_single_platform_down
	
	la $a0, platform3
	jal check_collision_single_platform_down
	
	move $ra, $s7 # restore $ra
	jr $ra
	
check_collision_platforms_right:
	move $s7, $ra # save $ra
	
	# check if start of platform x <= player's x <= end of platform x
	la $a0, platform1
	li $a1, PLAYER_MOVEMENT_RIGHT
	jal check_collision_single_platform_horizontal
	
	la $a0, platform2
	jal check_collision_single_platform_horizontal
	
	la $a0, platform3
	jal check_collision_single_platform_horizontal
	
	move $ra, $s7 # restore $ra
	jr $ra

gravity:
	# push $ra onto stack since multiple functions calls inside each other
	addi $sp, $sp, -4
	sw $ra, 0($sp)
	
	move $a1, $ra # load jump location for collision for bounds_down
	jal check_collision_bounds_down
	jal check_collision_platforms_down
	jal check_collision_cat_down
	jal clear_player
	addi $s1, $s1, 1
	jal draw_player
	
	lw $ra, 0($sp)
	addi $sp, $sp, 4
	
	jr $ra
	
check_collision_single_object_left: # $a0 stores object x, $a1, stores object y, $a2 stores offset to right side, $a3 stores address to jump to 
	addi $t0, $s0, PLAYER_MOVEMENT_LEFT # calculate next position
	addi $t1, $t0, 24 # calculate the player's right side
	addi $t2, $s1, 6 # calculate the player's feet
	
	add $t3, $a0, $a2 # calculate object's right side
	addi $t4, $a1, 5 # calculate the object's feet
	
	# check no collision conditions
	bgt $t0, $t3, no_collision 
	blt $t1, $a0, no_collision
	
	bgt $s1, $t4, no_collision
	blt $t2, $a1, no_collision
	
	jr $a3
	
check_collision_single_object_down: # $a0 stores object x, $a1, stores object y, $a2 stores offset to right side, $a3 stores address to jump to 
	addi $t0, $s1, PLAYER_MOVEMENT_DOWN # calculate next position
	addi $t1, $s0, 24 # calculate the player's right side
	addi $t2, $t0, 6 # calculate the player's feet
	
	add $t3, $a0, $a2 # calculate object's right side
	addi $t4, $a1, 5 # calculate the object's feet
	
	# check no collision conditions
	blt $t2, $a1, no_collision
	bgt $t0, $t4, no_collision
	
	bgt $s0, $t3, no_collision
	blt $t1, $a0, no_collision
	
	jr $a3
	
check_collision_single_object_right: # $a0 stores object x, $a1, stores object y, $a2 stores offset to right side, $a3 stores address to jump to 
	addi $t0, $s0, PLAYER_MOVEMENT_RIGHT # calculate next position
	addi $t1, $t0, 24 # calculate the player's right side
	addi $t2, $s1, 6 # calculate the player's feet
	
	add $t3, $a0, $a2 # calculate object's right side
	addi $t4, $a1, 5 # calculate the object's feet
	
	# check no collision conditions
	bgt $t0, $t3, no_collision 
	blt $t1, $a0, no_collision
	
	bgt $s1, $t4, no_collision
	blt $t2, $a1, no_collision
	
	jr $a3
	
check_collision_cat_left:
	move $s7, $ra
	
	la $t0, cat1 
	lw $a0, 0($t0) # put cat x in $a0
	lw $a1, 4($t0) # put cat y in $a1
	li $a2, 28 # put offset for right side of cat
	la $a3, lose_health # put where to jump to if collision occurred
	jal check_collision_single_object_left
	
	la $t0, cat2
	lw $a0, 0($t0)
	lw $a1, 4($t0)
	jal check_collision_single_object_left
	
	move $ra, $s7
	jr $ra
	
check_collision_cat_down:
	move $s7, $ra
	
	la $t0, cat1 
	lw $a0, 0($t0)
	lw $a1, 4($t0)
	li $a2, 28
	la $a3, lose_health
	jal check_collision_single_object_down
	
	la $t0, cat2
	lw $a0, 0($t0)
	lw $a1, 4($t0)
	jal check_collision_single_object_down
	
	move $ra, $s7
	jr $ra

check_collision_cat_right:
	move $s7, $ra
	
	la $t0, cat1 
	lw $a0, 0($t0)
	lw $a1, 4($t0)
	li $a2, 28
	la $a3, lose_health
	jal check_collision_single_object_right
	
	la $t0, cat2
	lw $a0, 0($t0)
	lw $a1, 4($t0)
	jal check_collision_single_object_right
	
	move $ra, $s7
	jr $ra

check_collision_cheese_left:
	move $s7, $ra
	
	la $t0, cheese 
	lw $a0, 0($t0) # put cheese x in $a0
	lw $a1, 4($t0) # put cheese y in $a1
	li $a2, 16
	la $a3, win_game
	jal check_collision_single_object_left
	
	move $ra, $s7
	jr $ra

check_collision_cheese_right:	
	move $s7, $ra
	
	la $t0, cheese 
	lw $a0, 0($t0) # put cheese x in $a0
	lw $a1, 4($t0) # put cheese y in $a1
	li $a2, 16
	la $a3, win_game
	jal check_collision_single_object_right
	
	move $ra, $s7
	jr $ra		

# -------- MOVING OBJECT FUNCTIONS --------
move_cat:
	la $t0, cat1
	lw $t1, 8($t0) # get direction of cat
	
	beq $t1, -1, move_cat_left
	j move_cat_right
	
move_cat_left:
	addi $sp, $sp, -4
	sw $ra, 0($sp)
	
	la $t7, cat1
	la $t1, platform2
	
	lw $t8, 0($t7) # get cat x position
	lw $t9, 4($t7) # get cat y position
	
	lw $t4, 0($t1) # get platform start x
	
	addi $t5, $t8, -4 # get new pos
	blt $t5, $t4, reverse_cat_direction
	
	# check ONLY cat1 collision
	la $t0, cat1 
	lw $a0, 0($t0) # put cat x in $a0
	lw $a1, 4($t0) # put cat y in $a1
	li $a2, 28 # put offset for right side of cat
	la $a3, lose_health # put where to jump to if collision occurred
	jal check_collision_single_object_right
	
	# move cat right
	move $a0, $t8
	move $a1, $t9
	jal clear_single_cat
	
	move $a0, $t5
	jal draw_single_cat
	
	# la $t0, cat1
	sw $t5, 0($t7)
	
	lw $ra, 0($sp)
	addi $sp, $sp, 4
	
	jr $ra

move_cat_right:	
	addi $sp, $sp, -4
	sw $ra, 0($sp)
	
	la $t7, cat1
	la $t1, platform2
	
	lw $t8, 0($t7) # get cat x position
	lw $t9, 4($t7) # get cat y position
	
	lw $t4, 4($t1) # get platform end x
	
	addi $t5, $t8, 4
	addi $t6, $t8, 32 # get cat's right side
	bgt $t6, $t4, reverse_cat_direction
	
	# check ONLY cat 1 collision
	la $t0, cat1 
	lw $a0, 0($t0) # put cat x in $a0
	lw $a1, 4($t0) # put cat y in $a1
	li $a2, 28 # put offset for right side of cat
	la $a3, lose_health # put where to jump to if collision occurred
	jal check_collision_single_object_left
	
	# move cat right
	move $a0, $t8
	move $a1, $t9
	jal clear_single_cat
	
	move $a0, $t5
	jal draw_single_cat
	
	# la $t0, cat1
	sw $t5, 0($t7)
	
	lw $ra, 0($sp)
	addi $sp, $sp, 4
	
	jr $ra
	
reverse_cat_direction: # $a0 stores the address to return to once direction is reversed
	la $t0, cat1
	lw $t1, 8($t0)
	sub $t1, $zero, $t1 # reverse direction by doing 0 - (curr direction)
	sw $t1, 8($t0)
	
	jr $ra
	
move_platform:
	la $t0, platform3
	lw $t1, 12($t0) # get direction of platform
	
	beq $t1, -1, move_platform_left
	j move_platform_right
	
move_platform_left:
	addi $sp, $sp, -4
	sw $ra, 0($sp)
	
	li $a0, PLAYER_MOVEMENT_RIGHT
	jal check_moving_platform_collision
	
	la $t0, platform3
	lw $t1, 0($t0) # start x of platform
	lw $t2, 4($t0) # end x of platform
	lw $t3, 8($t0) # y of platform
	
	ble $t1, $zero, reverse_platform_direction
	
	# draw platform moving left
	li $t4, DISPLAY_ADDRESS
	
	# erase end of platform
	li $t5, BACKGROUND_COLOUR
	sll $t3, $t3, 8
	add $t3, $t3, $t2
	add $t3, $t3, $t4 
	sw $t5, 0($t3)
	
	# draw new start x of platform
	li $t5, PLATFORM_COLOUR
	subi $t3, $t3, 88 # calculate new start x
	sw $t5, 0($t3)
	
	# adjust positions in memory
	addi $t1, $t1, -4
	addi $t2, $t2, -4
	sw $t1, 0($t0)
	sw $t2, 4($t0)
	
	lw $ra, 0($sp)
	addi $sp, $sp, 4
	
	jr $ra

move_platform_right:
	addi $sp, $sp, -4
	sw $ra, 0($sp)
	
	li $a0, PLAYER_MOVEMENT_LEFT
	jal check_moving_platform_collision
	
	la $t0, platform3
	lw $t1, 0($t0) # start x of platform
	lw $t2, 4($t0) # end x of platform
	lw $t3, 8($t0) # y of platform
	
	bge $t2, 250, reverse_platform_direction
	
	# draw platform moving right
	li $t4, DISPLAY_ADDRESS
	
	# erase start of platform
	li $t5, BACKGROUND_COLOUR
	sll $t3, $t3, 8
	add $t3, $t3, $t1
	add $t3, $t3, $t4 
	sw $t5, 0($t3)
	
	# draw new end x of platform
	li $t5, PLATFORM_COLOUR
	addi $t3, $t3, 88 # calculate new end x
	sw $t5, 0($t3)
	
	# adjust positions in memory
	addi $t1, $t1, 4
	addi $t2, $t2, 4
	sw $t1, 0($t0)
	sw $t2, 4($t0)
	
	lw $ra, 0($sp)
	addi $sp, $sp, 4
	
	jr $ra

reverse_platform_direction:
	# pop original $ra off
	lw $ra, 0($sp)
	addi $sp, $sp, 4
	
	la $t0, platform3
	lw $t1, 12($t0)
	sub $t1, $zero, $t1 # reverse direction by doing 0 - (curr direction)
	sw $t1, 12($t0)
	
	jr $ra


check_moving_platform_collision: # move player above platform if they collide with platform horizontally
	# $a0 stores next movement position
	la $t7, platform3
	add $t0, $s0, $a0 # calculate new position
	addi $t1, $t0, 24 # get player's right side
	
	move $t2, $s1 # player's start y
	addi $t3, $t2, 6 # player's feet

	lw $t4, 0($t7) # start of platform x
	lw $t5, 4($t7) # end of platform x
	lw $t6, 8($t7) # platform y
	
	# check if platform start x is less than player's right side x
	blt $t1, $t4, no_collision
	bgt $t0, $t5, no_collision
	
	# check if player start y <= platform y <= player end y
	blt $t6, $t2, no_collision
	bge $t6, $t3, no_collision
	
	j move_player_above_platform
	
move_player_above_platform:
	jal clear_player
	li $s1, 18
	jal draw_player
	
	j game_loop
		
# -------- HEALTH RELATED FUNCTIONS --------
lose_health:
	# reset player positions
	jal clear_player
	li $s0, 0
	li $s1, 45
	
	beq $s2, 3, clear_heart3
	beq $s2, 2, clear_heart2
	beq $s2, 1, clear_heart1

clear_heart3:
	addi $s2, $s2, -1 # reduce health
	move $s7, $ra # save $ra
	
	la $t0, heart3 # get address of heart 3
	lw $a0, 0($t0) # load position of heart 3
	jal clear_single_heart
	
	move $ra, $s7 # restore $ra
	
	j game_loop

clear_heart2:
	addi $s2, $s2, -1
	move $s7, $ra
	
	la $t0, heart2
	lw $a0, 0($t0)
	jal clear_single_heart
	
	move $ra, $s7
	
	j game_loop

clear_heart1:
	addi $s2, $s2, -1
	move $s7, $ra
	
	la $t0, heart1
	lw $a0, 0($t0)
	jal clear_single_heart
	
	move $ra, $s7
	
	j lose_game

# -------- LOSE/WIN FUNCTIONS --------
clear_screen: # $a0 takes in the colour to clear with
	li $t0, DISPLAY_ADDRESS
	move $t1, $a0
	# get end bound
	li $t2, 256
	sll $t2, $t2, 8
	add $t2, $t2, $t0
	
	clear_screen_loop:
		sw $t1, 0($t0)
		addi $t0, $t0, 4
		bne $t0, $t2, clear_screen_loop
		jr $ra
		
draw_lose_screen:
	li $t0, DISPLAY_ADDRESS
	addi $t0, $t0, 2584
	li $t1, RED
	
	# draw "GAME OVER" msg
	sw $t1, 4($t0)
	sw $t1, 8($t0)
	sw $t1, 12($t0)
	sw $t1, 28($t0)
	sw $t1, 32($t0)
	sw $t1, 36($t0)
	sw $t1, 48($t0)
	sw $t1, 64($t0)
	sw $t1, 72($t0)
	sw $t1, 76($t0)
	sw $t1, 80($t0)
	sw $t1, 84($t0)
	sw $t1, 88($t0)
	sw $t1, 120($t0)
	sw $t1, 124($t0)
	sw $t1, 128($t0)
	sw $t1, 140($t0)
	sw $t1, 156($t0)
	sw $t1, 164($t0)
	sw $t1, 168($t0)
	sw $t1, 172($t0)
	sw $t1, 176($t0)
	sw $t1, 180($t0)
	sw $t1, 188($t0)
	sw $t1, 192($t0)
	sw $t1, 196($t0)
	sw $t1, 200($t0)
	sw $t1, 256($t0)
	sw $t1, 272($t0)
	sw $t1, 280($t0)
	sw $t1, 296($t0)
	sw $t1, 304($t0)
	sw $t1, 308($t0)
	sw $t1, 316($t0)
	sw $t1, 320($t0)
	sw $t1, 328($t0)
	sw $t1, 372($t0)
	sw $t1, 388($t0)
	sw $t1, 396($t0)
	sw $t1, 412($t0)
	sw $t1, 420($t0)
	sw $t1, 444($t0)
	sw $t1, 460($t0)
	sw $t1, 512($t0)
	sw $t1, 536($t0)
	sw $t1, 552($t0)
	sw $t1, 560($t0)
	sw $t1, 568($t0)
	sw $t1, 576($t0)
	sw $t1, 584($t0)
	sw $t1, 588($t0)
	sw $t1, 592($t0)
	sw $t1, 596($t0)
	sw $t1, 600($t0)
	sw $t1, 628($t0)
	sw $t1, 644($t0)
	sw $t1, 652($t0)
	sw $t1, 668($t0)
	sw $t1, 676($t0)
	sw $t1, 680($t0)
	sw $t1, 684($t0)
	sw $t1, 688($t0)
	sw $t1, 692($t0)
	sw $t1, 700($t0)
	sw $t1, 716($t0)
	sw $t1, 768($t0)
	sw $t1, 780($t0)
	sw $t1, 784($t0)
	sw $t1, 792($t0)
	sw $t1, 796($t0)
	sw $t1, 800($t0)
	sw $t1, 804($t0)
	sw $t1, 808($t0)
	sw $t1, 816($t0)
	sw $t1, 824($t0)
	sw $t1, 832($t0)
	sw $t1, 840($t0)
	sw $t1, 884($t0)
	sw $t1, 900($t0)
	sw $t1, 908($t0)
	sw $t1, 924($t0)
	sw $t1, 932($t0)
	sw $t1, 956($t0)
	sw $t1, 960($t0)
	sw $t1, 964($t0)
	sw $t1, 968($t0)
	sw $t1, 1024($t0)
	sw $t1, 1040($t0)
	sw $t1, 1048($t0)
	sw $t1, 1064($t0)
	sw $t1, 1072($t0)
	sw $t1, 1080($t0)
	sw $t1, 1088($t0)
	sw $t1, 1096($t0)
	sw $t1, 1140($t0)
	sw $t1, 1156($t0)
	sw $t1, 1164($t0)
	sw $t1, 1176($t0)
	sw $t1, 1188($t0)
	sw $t1, 1212($t0)
	sw $t1, 1228($t0)
	sw $t1, 1284($t0)
	sw $t1, 1288($t0)
	sw $t1, 1292($t0)
	sw $t1, 1304($t0)
	sw $t1, 1320($t0)
	sw $t1, 1328($t0)
	sw $t1, 1344($t0)
	sw $t1, 1352($t0)
	sw $t1, 1356($t0)
	sw $t1, 1360($t0)
	sw $t1, 1364($t0)
	sw $t1, 1368($t0)
	sw $t1, 1400($t0)
	sw $t1, 1404($t0)
	sw $t1, 1408($t0)
	sw $t1, 1424($t0)
	sw $t1, 1428($t0)
	sw $t1, 1444($t0)
	sw $t1, 1448($t0)
	sw $t1, 1452($t0)
	sw $t1, 1456($t0)
	sw $t1, 1460($t0)
	sw $t1, 1468($t0)
	sw $t1, 1484($t0)
	
	jr $ra
	
draw_lose_hearts:
	move $s7, $ra
	li $t0, DISPLAY_ADDRESS
	
	addi $a0, $t0, 6476 # left heart
	jal draw_single_lose_heart
	
	addi $a0, $t0, 6516 # middle heart
	jal draw_single_lose_heart
	
	addi $a0, $t0, 6556 # right heart
	jal draw_single_lose_heart
	
	move $ra, $s7
	jr $ra
	
draw_single_lose_heart: # a0 takes in the position of the heart
	li $t1, LIGHT_GREY
	move $t3, $a0
	
	sw $t1, 0($t3)
	sw $t1, 4($t3)
	sw $t1, 16($t3)
	sw $t1, 20($t3)
	sw $t1, 256($t3)
	sw $t1, 260($t3)
	sw $t1, 268($t3)
	sw $t1, 272($t3)
	sw $t1, 276($t3)
	sw $t1, 512($t3)
	sw $t1, 516($t3)
	sw $t1, 524($t3)
	sw $t1, 528($t3)
	sw $t1, 532($t3)
	sw $t1, 772($t3)
	sw $t1, 776($t3)
	sw $t1, 784($t3)
	sw $t1, 1032($t3)
	
	jr $ra

lose_game:
	li $a0, BLACK
	jal clear_screen
	jal draw_lose_screen
	jal draw_lose_hearts
	jal draw_reset_text
	jal draw_quit_text
	j check_end_input
	
draw_win_screen:
	li $t0, DISPLAY_ADDRESS
	addi $t0, $t0, 2604
	li $t1, GREEN

	# draw "YOU WIN" msg
	sw $t1, 0($t0)
	sw $t1, 16($t0)
	sw $t1, 28($t0)
	sw $t1, 32($t0)
	sw $t1, 36($t0)
	sw $t1, 48($t0)
	sw $t1, 64($t0)
	sw $t1, 92($t0)
	sw $t1, 108($t0)
	sw $t1, 116($t0)
	sw $t1, 120($t0)
	sw $t1, 124($t0)
	sw $t1, 128($t0)
	sw $t1, 132($t0)
	sw $t1, 140($t0)
	sw $t1, 156($t0)
	sw $t1, 256($t0)
	sw $t1, 272($t0)
	sw $t1, 280($t0)
	sw $t1, 296($t0)
	sw $t1, 304($t0)
	sw $t1, 320($t0)
	sw $t1, 348($t0)
	sw $t1, 356($t0)
	sw $t1, 364($t0)
	sw $t1, 380($t0)
	sw $t1, 396($t0)
	sw $t1, 400($t0)
	sw $t1, 412($t0)
	sw $t1, 516($t0)
	sw $t1, 524($t0)
	sw $t1, 536($t0)
	sw $t1, 552($t0)
	sw $t1, 560($t0)
	sw $t1, 576($t0)
	sw $t1, 604($t0)
	sw $t1, 612($t0)
	sw $t1, 620($t0)
	sw $t1, 636($t0)
	sw $t1, 652($t0)
	sw $t1, 660($t0)
	sw $t1, 668($t0)
	sw $t1, 776($t0)
	sw $t1, 792($t0)
	sw $t1, 808($t0)
	sw $t1, 816($t0)
	sw $t1, 832($t0)
	sw $t1, 860($t0)
	sw $t1, 868($t0)
	sw $t1, 876($t0)
	sw $t1, 892($t0)
	sw $t1, 908($t0)
	sw $t1, 916($t0)
	sw $t1, 924($t0)
	sw $t1, 1032($t0)
	sw $t1, 1048($t0)
	sw $t1, 1064($t0)
	sw $t1, 1072($t0)
	sw $t1, 1088($t0)
	sw $t1, 1116($t0)
	sw $t1, 1120($t0)
	sw $t1, 1128($t0)
	sw $t1, 1132($t0)
	sw $t1, 1148($t0)
	sw $t1, 1164($t0)
	sw $t1, 1176($t0)
	sw $t1, 1180($t0)
	sw $t1, 1288($t0)
	sw $t1, 1308($t0)
	sw $t1, 1312($t0)
	sw $t1, 1316($t0)
	sw $t1, 1332($t0)
	sw $t1, 1336($t0)
	sw $t1, 1340($t0)
	sw $t1, 1372($t0)
	sw $t1, 1388($t0)
	sw $t1, 1396($t0)
	sw $t1, 1400($t0)
	sw $t1, 1404($t0)
	sw $t1, 1408($t0)
	sw $t1, 1412($t0)
	sw $t1, 1420($t0)
	sw $t1, 1436($t0)
	
	jr $ra

win_game:
	li $a0, BLACK
	jal clear_screen
	jal draw_win_screen
	jal draw_win_hearts
	jal draw_reset_text
	jal draw_quit_text
	j check_end_input
	
draw_win_hearts:
	move $s7, $ra
	li $t0, DISPLAY_ADDRESS
	beq $s2, 1, draw_win_hearts1
	beq $s2, 2, draw_win_hearts2
	
	addi $a0, $t0, 6476 # left heart
	jal draw_single_heart
	
	addi $a0, $t0, 6516 # middle heart
	jal draw_single_heart
	
	addi $a0, $t0, 6556 # right heart
	jal draw_single_heart
	
	move $ra, $s7
	jr $ra

	draw_win_hearts1:
		addi $a0, $t0, 6516 # middle heart
		jal draw_single_heart
	
		move $ra, $s7
		jr $ra
		
	draw_win_hearts2:
		addi $a0, $t0, 6484 # left heart
		jal draw_single_heart
	
		addi $a0, $t0, 6548 # right heart
		jal draw_single_heart
	
		move $ra, $s7
		jr $ra
		
	
draw_reset_text:
	li $t0, DISPLAY_ADDRESS
	addi $t0, $t0, 10248
	li $t1, RED
	
        sw $t1, 0($t0)
        sw $t1, 4($t0)
        sw $t1, 16($t0)
        sw $t1, 20($t0)
        sw $t1, 32($t0)
        sw $t1, 36($t0)
        sw $t1, 40($t0)
        sw $t1, 52($t0)
        sw $t1, 56($t0)
        sw $t1, 68($t0)
        sw $t1, 72($t0)
        sw $t1, 92($t0)
        sw $t1, 96($t0)
        sw $t1, 120($t0)
        sw $t1, 124($t0)
        sw $t1, 128($t0)
        sw $t1, 140($t0)
        sw $t1, 164($t0)
        sw $t1, 168($t0)
        sw $t1, 180($t0)
        sw $t1, 184($t0)
        sw $t1, 188($t0)
        sw $t1, 200($t0)
        sw $t1, 204($t0)
        sw $t1, 212($t0)
        sw $t1, 216($t0)
        sw $t1, 220($t0)
        sw $t1, 228($t0)
        sw $t1, 232($t0)
        sw $t1, 236($t0)
        sw $t1, 256($t0)
        sw $t1, 264($t0)
        sw $t1, 272($t0)
        sw $t1, 280($t0)
        sw $t1, 288($t0)
        sw $t1, 304($t0)
        sw $t1, 320($t0)
        sw $t1, 348($t0)
        sw $t1, 356($t0)
        sw $t1, 380($t0)
        sw $t1, 392($t0)
        sw $t1, 400($t0)
        sw $t1, 420($t0)
        sw $t1, 428($t0)
        sw $t1, 436($t0)
        sw $t1, 452($t0)
        sw $t1, 468($t0)
        sw $t1, 488($t0)
        sw $t1, 512($t0)
        sw $t1, 516($t0)
        sw $t1, 528($t0)
        sw $t1, 532($t0)
        sw $t1, 544($t0)
        sw $t1, 548($t0)
        sw $t1, 564($t0)
        sw $t1, 580($t0)
        sw $t1, 604($t0)
        sw $t1, 608($t0)
        sw $t1, 636($t0)
        sw $t1, 648($t0)
        sw $t1, 656($t0)
        sw $t1, 676($t0)
        sw $t1, 680($t0)
        sw $t1, 692($t0)
        sw $t1, 696($t0)
        sw $t1, 712($t0)
        sw $t1, 724($t0)
        sw $t1, 728($t0)
        sw $t1, 744($t0)
        sw $t1, 768($t0)
        sw $t1, 784($t0)
        sw $t1, 792($t0)
        sw $t1, 800($t0)
        sw $t1, 824($t0)
        sw $t1, 840($t0)
        sw $t1, 860($t0)
        sw $t1, 868($t0)
        sw $t1, 892($t0)
        sw $t1, 904($t0)
        sw $t1, 912($t0)
        sw $t1, 932($t0)
        sw $t1, 940($t0)
        sw $t1, 948($t0)
        sw $t1, 972($t0)
        sw $t1, 980($t0)
        sw $t1, 1000($t0)
        sw $t1, 1024($t0)
        sw $t1, 1040($t0)
        sw $t1, 1048($t0)
        sw $t1, 1056($t0)
        sw $t1, 1060($t0)
        sw $t1, 1064($t0)
        sw $t1, 1072($t0)
        sw $t1, 1076($t0)
        sw $t1, 1088($t0)
        sw $t1, 1092($t0)
        sw $t1, 1116($t0)
        sw $t1, 1124($t0)
        sw $t1, 1148($t0)
        sw $t1, 1164($t0)
        sw $t1, 1188($t0)
        sw $t1, 1196($t0)
        sw $t1, 1204($t0)
        sw $t1, 1208($t0)
        sw $t1, 1212($t0)
        sw $t1, 1220($t0)
        sw $t1, 1224($t0)
        sw $t1, 1236($t0)
        sw $t1, 1240($t0)
        sw $t1, 1244($t0)
        sw $t1, 1256($t0)
	
	jr $ra
	
draw_quit_text:
	li $t0, DISPLAY_ADDRESS
	addi $t0, $t0, 12816
	li $t1, RED
	
	sw $t1, 0($t0)
        sw $t1, 4($t0)
        sw $t1, 16($t0)
        sw $t1, 20($t0)
        sw $t1, 32($t0)
        sw $t1, 36($t0)
        sw $t1, 40($t0)
        sw $t1, 52($t0)
        sw $t1, 56($t0)
        sw $t1, 68($t0)
        sw $t1, 72($t0)
        sw $t1, 96($t0)
        sw $t1, 120($t0)
        sw $t1, 124($t0)
        sw $t1, 128($t0)
        sw $t1, 140($t0)
        sw $t1, 168($t0)
        sw $t1, 180($t0)
        sw $t1, 188($t0)
        sw $t1, 196($t0)
        sw $t1, 200($t0)
        sw $t1, 204($t0)
        sw $t1, 212($t0)
        sw $t1, 216($t0)
        sw $t1, 220($t0)
        sw $t1, 256($t0)
        sw $t1, 264($t0)
        sw $t1, 272($t0)
        sw $t1, 280($t0)
        sw $t1, 288($t0)
        sw $t1, 304($t0)
        sw $t1, 320($t0)
        sw $t1, 348($t0)
        sw $t1, 356($t0)
        sw $t1, 380($t0)
        sw $t1, 392($t0)
        sw $t1, 400($t0)
        sw $t1, 420($t0)
        sw $t1, 428($t0)
        sw $t1, 436($t0)
        sw $t1, 444($t0)
        sw $t1, 456($t0)
        sw $t1, 472($t0)
        sw $t1, 512($t0)
        sw $t1, 516($t0)
        sw $t1, 528($t0)
        sw $t1, 532($t0)
        sw $t1, 544($t0)
        sw $t1, 548($t0)
        sw $t1, 564($t0)
        sw $t1, 580($t0)
        sw $t1, 604($t0)
        sw $t1, 612($t0)
        sw $t1, 636($t0)
        sw $t1, 648($t0)
        sw $t1, 656($t0)
        sw $t1, 676($t0)
        sw $t1, 684($t0)
        sw $t1, 692($t0)
        sw $t1, 700($t0)
        sw $t1, 712($t0)
        sw $t1, 728($t0)
        sw $t1, 768($t0)
        sw $t1, 784($t0)
        sw $t1, 792($t0)
        sw $t1, 800($t0)
        sw $t1, 824($t0)
        sw $t1, 840($t0)
        sw $t1, 864($t0)
        sw $t1, 868($t0)
        sw $t1, 892($t0)
        sw $t1, 904($t0)
        sw $t1, 912($t0)
        sw $t1, 936($t0)
        sw $t1, 940($t0)
        sw $t1, 948($t0)
        sw $t1, 956($t0)
        sw $t1, 968($t0)
        sw $t1, 984($t0)
        sw $t1, 1024($t0)
        sw $t1, 1040($t0)
        sw $t1, 1048($t0)
        sw $t1, 1056($t0)
        sw $t1, 1060($t0)
        sw $t1, 1064($t0)
        sw $t1, 1072($t0)
        sw $t1, 1076($t0)
        sw $t1, 1088($t0)
        sw $t1, 1092($t0)
        sw $t1, 1124($t0)
        sw $t1, 1148($t0)
        sw $t1, 1164($t0)
        sw $t1, 1196($t0)
        sw $t1, 1204($t0)
        sw $t1, 1208($t0)
        sw $t1, 1212($t0)
        sw $t1, 1220($t0)
        sw $t1, 1224($t0)
        sw $t1, 1228($t0)
        sw $t1, 1240($t0)
	
	jr $ra
	
check_end_input:
	li $t9, KEYBOARD_ADDRESS # init the keyboard
	lw $t8, 0($t9) # load contents of new keypress
	beq $t8, 1, keypress_end_happened # check if a key was pressed
	
keypress_end_happened:
	lw $t2, 4($t9) # load which key was pressed
	
	beq $t2, 0x71, q_pressed
	beq $t2, 0x72, r_pressed
	
	j check_end_input
	
check_start_input:
	li $t9, KEYBOARD_ADDRESS # init the keyboard
	lw $t8, 0($t9) # load contents of new keypress
	beq $t8, 1, keypress_start_happened # check if a key was pressed
	j check_start_input
	
keypress_start_happened:
	lw $t2, 4($t9)
	
	beq $t2, 0x77, w_pressed_start
	beq $t2, 0x61, a_pressed_start
	beq $t2, 0x73, s_pressed_start
	beq $t2, 0x64, d_pressed_start
	beq $t2, 0x70, p_pressed
	
	j check_start_input
	
w_pressed_start:
	beq $s6, 1, clear_exit_cursor
	
	move_cursor_to_start:
		li $s6, 0 # set cursor to start game
		li $a0, 160
		li $a1, 40
		jal draw_cheese
	
	j check_start_input
	
a_pressed_start:
	blt $s0, 8, check_start_input
	
	jal clear_player
	addi $s0, $s0, PLAYER_MOVEMENT_LEFT # move player left
	jal draw_player
	
	j check_start_input

s_pressed_start:
	beq $s6, 0, clear_start_cursor
	
	move_cursor_to_end:
		li $s6, 1 # set cursor to end game
		li $a0, 160
		li $a1, 50
		jal draw_cheese
	
	j check_start_input
	
d_pressed_start:
	bge $s0, 224, check_start_input
	
	jal clear_player
	addi $s0, $s0, PLAYER_MOVEMENT_RIGHT # move player right
	jal draw_player
	
	j check_start_input

p_pressed:
	beq $s6, 0, init_game
	j end_main
	
clear_exit_cursor:
	li $a0, 160
	li $a1, 50
	jal clear_cheese
	j move_cursor_to_start

clear_start_cursor:
	li $a0, 160
	li $a1, 40
	jal clear_cheese
	j move_cursor_to_end

# -------- DRAWING FUNCTIONS --------
draw_player:
	# load where the player should be drawn on display
	li $t0, DISPLAY_ADDRESS
	add $t0, $t0, $s0
	li $t1, 256 # get width of bitmap
	mult $t1, $s1 # get y-offset of player
	mflo $t1 # put y-offset in $t1
	add $t0, $t0, $t1
	
	# start drawing the player
	li $t1, GREY
	sw $t1, 4($t0)
	sw $t1, 24($t0)
	sw $t1, 264($t0)
	sw $t1, 268($t0)
	sw $t1, 272($t0)
	sw $t1, 276($t0)
	sw $t1, 512($t0)
	sw $t1, 520($t0)
	sw $t1, 528($t0)
	sw $t1, 768($t0)
	sw $t1, 776($t0)
	sw $t1, 780($t0)
	sw $t1, 784($t0)
	sw $t1, 1028($t0)
	sw $t1, 1032($t0)
	sw $t1, 1036($t0)
	sw $t1, 1040($t0)
	sw $t1, 1044($t0)
	sw $t1, 1288($t0)
	sw $t1, 1300($t0)
	
	li $t1, BLACK
	sw $t1, 524($t0)
	sw $t1, 532($t0)
	
	li $t1, RED
	sw $t1, 788($t0)
	
	jr $ra
	
clear_player:
	# load where the player should be drawn on display
	li $t0, DISPLAY_ADDRESS
	add $t0, $t0, $s0
	li $t1, 256 # get width of bitmap
	mult $t1, $s1 # get y-offset of player
	mflo $t1 # put y-offset in $t1
	add $t0, $t0, $t1
	
	# fill the player's position with the background colour
	li $t1, BACKGROUND_COLOUR
	sw $t1, 4($t0)
	sw $t1, 24($t0)
	sw $t1, 264($t0)
	sw $t1, 268($t0)
	sw $t1, 272($t0)
	sw $t1, 276($t0)
	sw $t1, 512($t0)
	sw $t1, 520($t0)
	sw $t1, 528($t0)
	sw $t1, 768($t0)
	sw $t1, 776($t0)
	sw $t1, 780($t0)
	sw $t1, 784($t0)
	sw $t1, 1028($t0)
	sw $t1, 1032($t0)
	sw $t1, 1036($t0)
	sw $t1, 1040($t0)
	sw $t1, 1044($t0)
	sw $t1, 1288($t0)
	sw $t1, 1300($t0)
	sw $t1, 524($t0)
	sw $t1, 532($t0)
	sw $t1, 788($t0)
	
	jr $ra
	
draw_game_background:
	li $t0, DISPLAY_ADDRESS
	li $t1, BACKGROUND_COLOUR # set background colour
	addi $t2, $t0, 13056 # set where to stop drawing background
	
	draw_game_background_loop:
		sw $t1, 0($t0) # draw background
		addi $t0, $t0, 4
		blt $t0, $t2, draw_game_background_loop
		addi $t2, $t0, 256 # set bound for when to stop drawing the floor
		
	draw_game_background_floor_loop:
		li $t1, PLATFORM_COLOUR # set floor colour
		sw $t1, 0($t0) # draw floor
		addi $t0, $t0, 4
		blt $t0, $t2, draw_game_background_floor_loop
		jr $ra
		
draw_all_platforms:
	# avoid using stack by using $ao - $a2, where $s7 stores $ra
	move $s7, $ra
	
	# draw platform 1
	la $t1, platform1 # load address of platform 1
	lw $t2, 0($t1) # load start value
	lw $t3, 4($t1) # load end value
	lw $t4, 8($t1) # load y val
	
	move $a0, $t2
	move $a1, $t3
	move $a2, $t4
	jal draw_platform
	
	# draw platform 2
	la $t1, platform2 # load address of platform 2
	lw $t2, 0($t1)
	lw $t3, 4($t1)
	lw $t4, 8($t1) 
	
	move $a0, $t2
	move $a1, $t3
	move $a2, $t4
	jal draw_platform
	
	la $t1, platform3 # load address of platform 2
	lw $t2, 0($t1)
	lw $t3, 4($t1)
	lw $t4, 8($t1) 
	
	move $a0, $t2
	move $a1, $t3
	move $a2, $t4
	jal draw_platform
	
	move $ra, $s7 # restore $ra
	
	jr $ra
	
draw_platform: # draw_platform(start, end), draws a platform from start to end
	li $t0, DISPLAY_ADDRESS
	li $t1, PLATFORM_COLOUR
	
	move $t2, $a0 # start x
	move $t3, $a1 # end x
	move $t4, $a2 # y pos
	
	sll $t4, $t4, 8 # multiply y by 256 to get row pixel
	add $t2, $t2, $t4
	add $t3, $t3, $t4
	
	add $t2, $t2, $t0 # add display address to start
	add $t3, $t3, $t0 # add display address to end
	
	draw_platform_loop:
		sw $t1, 0($t2)
		addi $t2, $t2, 4
		ble $t2, $t3, draw_platform_loop
		jr $ra
		
draw_hearts:
	li $t0, DISPLAY_ADDRESS
	move $s7, $ra # save $ra in $s7
	
	la $t2, heart1
	lw $t3, 0($t2)
	add $t3, $t0, $t3
	move $a0, $t3
	jal draw_single_heart

	la $t2, heart2
	lw $t3, 0($t2)
	add $t3, $t0, $t3
	move $a0, $t3
	jal draw_single_heart 
	
	la $t2, heart3
	lw $t3, 0($t2)
	add $t3, $t0, $t3
	move $a0, $t3
	jal draw_single_heart
	
	move $ra, $s7 # restore $ra
	
	jr $ra
	
draw_single_heart: # $a0 represents where to draw the heart on the bitdisplay
	li $t1, RED
	move $t3, $a0
	
	sw $t1, 0($t3)
	sw $t1, 4($t3)
	sw $t1, 16($t3)
	sw $t1, 20($t3)
	sw $t1, 256($t3)
	sw $t1, 260($t3)
	sw $t1, 264($t3)
	sw $t1, 268($t3)
	sw $t1, 272($t3)
	sw $t1, 276($t3)
	sw $t1, 512($t3)
	sw $t1, 516($t3)
	sw $t1, 520($t3)
	sw $t1, 524($t3)
	sw $t1, 528($t3)
	sw $t1, 532($t3)
	sw $t1, 772($t3)
	sw $t1, 776($t3)
	sw $t1, 780($t3)
	sw $t1, 784($t3)
	sw $t1, 1032($t3)
	sw $t1, 1036($t3)
	
	jr $ra
	
clear_single_heart: # $a0 represents the position of the heart to clear
	li $t0, DISPLAY_ADDRESS
	li $t1, BLACK
	add $t3, $t0, $a0
	
	sw $t1, 0($t3)
	sw $t1, 4($t3)
	sw $t1, 16($t3)
	sw $t1, 20($t3)
	sw $t1, 256($t3)
	sw $t1, 260($t3)
	sw $t1, 264($t3)
	sw $t1, 268($t3)
	sw $t1, 272($t3)
	sw $t1, 276($t3)
	sw $t1, 512($t3)
	sw $t1, 516($t3)
	sw $t1, 520($t3)
	sw $t1, 524($t3)
	sw $t1, 528($t3)
	sw $t1, 532($t3)
	sw $t1, 772($t3)
	sw $t1, 776($t3)
	sw $t1, 780($t3)
	sw $t1, 784($t3)
	sw $t1, 1032($t3)
	sw $t1, 1036($t3)
	
	jr $ra
	
draw_cheese: # $a0, $a1 takes in the cheese's x, y position respectively
	li $t0, DISPLAY_ADDRESS
	sll $t4, $a1, 8
	add $t3, $a0, $t4 # get pixel position of cheese
	add $t0, $t0, $t3 # add to display address
	
	li $t1, DARK_YELLOW
	sw $t1, 4($t0)
	sw $t1, 8($t0)
	sw $t1, 12($t0)
	sw $t1, 268($t0)
	sw $t1, 528($t0)
	sw $t1, 784($t0)
	
	li $t1, YELLOW
	sw $t1, 260($t0)
	sw $t1, 264($t0)
	sw $t1, 512($t0)
	sw $t1, 516($t0)
	sw $t1, 524($t0)
	sw $t1, 772($t0)
	sw $t1, 776($t0)
	sw $t1, 780($t0)
	
	li $t1, HOLE_COLOUR
	sw $t1, 520($t0)
	sw $t1, 768($t0)
	
	jr $ra
	
clear_cheese: # $a0 and $a1 represent the cheese's x, y position respectively
	li $t0, DISPLAY_ADDRESS
	sll $t4, $a1, 8
	add $t3, $a0, $t4 # get pixel position of cheese
	add $t0, $t0, $t3 # add to display address
	
	li $t1, BACKGROUND_COLOUR
	sw $t1, 4($t0)
	sw $t1, 8($t0)
	sw $t1, 12($t0)
	sw $t1, 268($t0)
	sw $t1, 528($t0)
	sw $t1, 784($t0)
	sw $t1, 260($t0)
	sw $t1, 264($t0)
	sw $t1, 512($t0)
	sw $t1, 516($t0)
	sw $t1, 524($t0)
	sw $t1, 772($t0)
	sw $t1, 776($t0)
	sw $t1, 780($t0)
	sw $t1, 520($t0)
	sw $t1, 768($t0)
	
	jr $ra

draw_all_cats:
	move $s7, $ra
	
	la $t1, cat1
	lw $t2, 0($t1)
	lw $t3, 4($t1)
	move $a0, $t2
	move $a1, $t3
	jal draw_single_cat
	
	la $t1, cat2
	lw $t2, 0($t1)
	lw $t3, 4($t1)
	move $a0, $t2
	move $a1, $t3
	jal draw_single_cat
	
	move $ra, $s7
	
	jr $ra
		
draw_single_cat: # $a0 takes in cat's x pos, $a1 takes in cat's y-pos
	li $t0, DISPLAY_ADDRESS
	sll $t4, $a1, 8
	add $t3, $a0, $t4 # get pixel position of cat
	add $t0, $t0, $t3 # add to display address
	
	li $t1, BLACK
	sw $t1, 16($t0)
	sw $t1, 28($t0)
	sw $t1, 260($t0)
	sw $t1, 272($t0)
	sw $t1, 276($t0)
	sw $t1, 280($t0)
	sw $t1, 284($t0)
	sw $t1, 512($t0)
	sw $t1, 520($t0)
	sw $t1, 524($t0)
	sw $t1, 528($t0)
	sw $t1, 536($t0)
	sw $t1, 776($t0)
	sw $t1, 780($t0)
	sw $t1, 784($t0)
	sw $t1, 788($t0)
	sw $t1, 792($t0)
	sw $t1, 796($t0)
	sw $t1, 1028($t0)
	sw $t1, 1044($t0)
	sw $t1, 1052($t0)
	
	li $t1, LIGHT_BLUE
	sw $t1, 532($t0)
	sw $t1, 540($t0)
	
	jr $ra

clear_single_cat: # $a0 takes in cat's x pos, $a1 takes in cat's y pos
	li $t0, DISPLAY_ADDRESS

	sll $t4, $a1, 8
	add $t3, $a0, $t4 # get pixel position of cat
	add $t0, $t0, $t3 # add to display address
	
	li $t1, BACKGROUND_COLOUR
	sw $t1, 16($t0)
	sw $t1, 28($t0)
	sw $t1, 260($t0)
	sw $t1, 272($t0)
	sw $t1, 276($t0)
	sw $t1, 280($t0)
	sw $t1, 284($t0)
	sw $t1, 512($t0)
	sw $t1, 520($t0)
	sw $t1, 524($t0)
	sw $t1, 528($t0)
	sw $t1, 536($t0)
	sw $t1, 776($t0)
	sw $t1, 780($t0)
	sw $t1, 784($t0)
	sw $t1, 788($t0)
	sw $t1, 792($t0)
	sw $t1, 796($t0)
	sw $t1, 1028($t0)
	sw $t1, 1044($t0)
	sw $t1, 1052($t0)
	sw $t1, 532($t0)
	sw $t1, 540($t0)
	
	jr $ra
	
draw_game_title_top:
	li $t0, DISPLAY_ADDRESS
	li $t1, DARK_YELLOW
	
	addi $t0, $t0, 2612
	
        sw $t1, 4($t0)
        sw $t1, 8($t0)
        sw $t1, 12($t0)
        sw $t1, 24($t0)
        sw $t1, 40($t0)
        sw $t1, 48($t0)
        sw $t1, 52($t0)
        sw $t1, 56($t0)
        sw $t1, 60($t0)
        sw $t1, 64($t0)
        sw $t1, 72($t0)
        sw $t1, 76($t0)
        sw $t1, 80($t0)
        sw $t1, 84($t0)
        sw $t1, 88($t0)
        sw $t1, 100($t0)
        sw $t1, 104($t0)
        sw $t1, 108($t0)
        sw $t1, 112($t0)
        sw $t1, 120($t0)
        sw $t1, 124($t0)
        sw $t1, 128($t0)
        sw $t1, 132($t0)
        sw $t1, 136($t0)
        sw $t1, 256($t0)
        sw $t1, 272($t0)
        sw $t1, 280($t0)
        sw $t1, 296($t0)
        sw $t1, 304($t0)
        sw $t1, 328($t0)
        sw $t1, 352($t0)
        sw $t1, 376($t0)
        sw $t1, 512($t0)
        sw $t1, 536($t0)
        sw $t1, 552($t0)
        sw $t1, 560($t0)
        sw $t1, 564($t0)
        sw $t1, 568($t0)
        sw $t1, 572($t0)
        sw $t1, 576($t0)
        sw $t1, 584($t0)
        sw $t1, 588($t0)
        sw $t1, 592($t0)
        sw $t1, 596($t0)
        sw $t1, 600($t0)
        sw $t1, 612($t0)
        sw $t1, 616($t0)
        sw $t1, 620($t0)
        sw $t1, 632($t0)
        sw $t1, 636($t0)
        sw $t1, 640($t0)
        sw $t1, 644($t0)
        sw $t1, 648($t0)
        sw $t1, 768($t0)
        sw $t1, 792($t0)
        sw $t1, 796($t0)
        sw $t1, 800($t0)
        sw $t1, 804($t0)
        sw $t1, 808($t0)
        sw $t1, 816($t0)
        sw $t1, 840($t0)
        sw $t1, 880($t0)
        sw $t1, 888($t0)
        sw $t1, 1024($t0)
        sw $t1, 1040($t0)
        sw $t1, 1048($t0)
        sw $t1, 1064($t0)
        sw $t1, 1072($t0)
        sw $t1, 1096($t0)
        sw $t1, 1136($t0)
        sw $t1, 1144($t0)
        sw $t1, 1284($t0)
        sw $t1, 1288($t0)
        sw $t1, 1292($t0)
        sw $t1, 1304($t0)
        sw $t1, 1320($t0)
        sw $t1, 1328($t0)
        sw $t1, 1332($t0)
        sw $t1, 1336($t0)
        sw $t1, 1340($t0)
        sw $t1, 1344($t0)
        sw $t1, 1352($t0)
        sw $t1, 1356($t0)
        sw $t1, 1360($t0)
        sw $t1, 1364($t0)
        sw $t1, 1368($t0)
        sw $t1, 1376($t0)
        sw $t1, 1380($t0)
        sw $t1, 1384($t0)
        sw $t1, 1388($t0)
        sw $t1, 1400($t0)
        sw $t1, 1404($t0)
        sw $t1, 1408($t0)
        sw $t1, 1412($t0)
        sw $t1, 1416($t0)
        
        jr $ra
        
draw_game_title_bottom:
	li $t0, DISPLAY_ADDRESS
	li $t1, DARK_YELLOW
	
	addi $t0, $t0, 4404 # top title x + 1792
	
        sw $t1, 4($t0)
        sw $t1, 8($t0)
        sw $t1, 12($t0)
        sw $t1, 24($t0)
        sw $t1, 40($t0)
        sw $t1, 52($t0)
        sw $t1, 56($t0)
        sw $t1, 60($t0)
        sw $t1, 76($t0)
        sw $t1, 80($t0)
        sw $t1, 84($t0)
        sw $t1, 88($t0)
        sw $t1, 96($t0)
        sw $t1, 100($t0)
        sw $t1, 104($t0)
        sw $t1, 108($t0)
        sw $t1, 112($t0)
        sw $t1, 256($t0)
        sw $t1, 272($t0)
        sw $t1, 280($t0)
        sw $t1, 296($t0)
        sw $t1, 304($t0)
        sw $t1, 320($t0)
        sw $t1, 328($t0)
        sw $t1, 352($t0)
        sw $t1, 512($t0)
        sw $t1, 536($t0)
        sw $t1, 552($t0)
        sw $t1, 560($t0)
        sw $t1, 576($t0)
        sw $t1, 588($t0)
        sw $t1, 592($t0)
        sw $t1, 596($t0)
        sw $t1, 608($t0)
        sw $t1, 612($t0)
        sw $t1, 616($t0)
        sw $t1, 620($t0)
        sw $t1, 624($t0)
        sw $t1, 768($t0)
        sw $t1, 792($t0)
        sw $t1, 796($t0)
        sw $t1, 800($t0)
        sw $t1, 804($t0)
        sw $t1, 808($t0)
        sw $t1, 816($t0)
        sw $t1, 820($t0)
        sw $t1, 824($t0)
        sw $t1, 828($t0)
        sw $t1, 832($t0)
        sw $t1, 856($t0)
        sw $t1, 864($t0)
        sw $t1, 1024($t0)
        sw $t1, 1040($t0)
        sw $t1, 1048($t0)
        sw $t1, 1064($t0)
        sw $t1, 1072($t0)
        sw $t1, 1088($t0)
        sw $t1, 1112($t0)
        sw $t1, 1120($t0)
        sw $t1, 1284($t0)
        sw $t1, 1288($t0)
        sw $t1, 1292($t0)
        sw $t1, 1304($t0)
        sw $t1, 1320($t0)
        sw $t1, 1328($t0)
        sw $t1, 1344($t0)
        sw $t1, 1352($t0)
        sw $t1, 1356($t0)
        sw $t1, 1360($t0)
        sw $t1, 1364($t0)
        sw $t1, 1376($t0)
        sw $t1, 1380($t0)
        sw $t1, 1384($t0)
        sw $t1, 1388($t0)
        sw $t1, 1392($t0)
        
        jr $ra
        
draw_start_play:
	li $t0, DISPLAY_ADDRESS
	li $t1, RED
	
	addi $t0, $t0, 10292
	
	sw $t1, 4($t0)
        sw $t1, 8($t0)
        sw $t1, 16($t0)
        sw $t1, 20($t0)
        sw $t1, 24($t0)
        sw $t1, 36($t0)
        sw $t1, 48($t0)
        sw $t1, 52($t0)
        sw $t1, 64($t0)
        sw $t1, 68($t0)
        sw $t1, 72($t0)
        sw $t1, 256($t0)
        sw $t1, 276($t0)
        sw $t1, 288($t0)
        sw $t1, 296($t0)
        sw $t1, 304($t0)
        sw $t1, 312($t0)
        sw $t1, 324($t0)
        sw $t1, 516($t0)
        sw $t1, 532($t0)
        sw $t1, 544($t0)
        sw $t1, 548($t0)
        sw $t1, 552($t0)
        sw $t1, 560($t0)
        sw $t1, 564($t0)
        sw $t1, 580($t0)
        sw $t1, 776($t0)
        sw $t1, 788($t0)
        sw $t1, 800($t0)
        sw $t1, 808($t0)
        sw $t1, 816($t0)
        sw $t1, 824($t0)
        sw $t1, 836($t0)
        sw $t1, 1024($t0)
        sw $t1, 1028($t0)
        sw $t1, 1044($t0)
        sw $t1, 1056($t0)
        sw $t1, 1064($t0)
        sw $t1, 1072($t0)
        sw $t1, 1080($t0)
        sw $t1, 1092($t0)
        
        jr $ra
        
draw_start_exit:
	li $t0, DISPLAY_ADDRESS
	li $t1, RED
	
	addi $t0, $t0, 12852
	
        sw $t1, 0($t0)
        sw $t1, 4($t0)
        sw $t1, 8($t0)
        sw $t1, 16($t0)
        sw $t1, 24($t0)
        sw $t1, 32($t0)
        sw $t1, 36($t0)
        sw $t1, 40($t0)
        sw $t1, 48($t0)
        sw $t1, 52($t0)
        sw $t1, 56($t0)
        sw $t1, 256($t0)
        sw $t1, 272($t0)
        sw $t1, 280($t0)
        sw $t1, 292($t0)
        sw $t1, 308($t0)
        sw $t1, 512($t0)
        sw $t1, 516($t0)
        sw $t1, 532($t0)
        sw $t1, 548($t0)
        sw $t1, 564($t0)
        sw $t1, 768($t0)
        sw $t1, 784($t0)
        sw $t1, 792($t0)
        sw $t1, 804($t0)
        sw $t1, 820($t0)
        sw $t1, 1024($t0)
        sw $t1, 1028($t0)
        sw $t1, 1032($t0)
        sw $t1, 1040($t0)
        sw $t1, 1048($t0)
        sw $t1, 1056($t0)
        sw $t1, 1060($t0)
        sw $t1, 1064($t0)
        sw $t1, 1076($t0)
        
        jr $ra
	
draw_start_screen:
	li $s6, 0
	li $s0, 40
	li $s1, 30
	jal draw_player
	jal draw_game_title_top
	jal draw_game_title_bottom
	jal draw_start_play
	jal draw_start_exit
	li $a0, 160
	li $a1, 40 # 40 for start
	jal draw_cheese
	j check_start_input
