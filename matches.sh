#!/bin/bash

# REQUIRES:
# Discord.sh - https://github.com/ChaoticWeg/discord.sh
# jq - Used for JSON parsing
# curl - Interacting with the GW2 API and sending payload to Discord

# Script to output the WvW match-up for the coming weekly reset.
# Will post to specified Discord channel using Webhook
# Written in Bash because I can.

set -eo pipefail

# ID of home world
world=2008
region=${world:0:1}

channel="announcements"
username="Matchup"
# Webhook URL
hook=

match_log=/usr/local/bin/matches/matches.log

red="0xd32f2f"
green="0x28b463"
blue="0x039be5"

world_overview=$(curl --silent https://api.guildwars2.com/v2/wvw/matches/overview?world=$world)
all_matches=$(curl --silent https://api.guildwars2.com/v2/wvw/matches?ids=all)

curr_tier=$(echo $world_overview | jq '.id' --raw-output | awk --field-separator '-' '{print $2}')
curr_tier_arr=$(($curr_tier-1))

# Get maximum tiers for region
max_tiers=$(echo $all_matches | jq '.[].id' --compact-output | grep -c $region-)

# Get world current colour
if [ $(echo $world_overview | jq '.all_worlds.red' --compact-output | grep $world) ]
then
        curr_colour="red"
elif [ $(echo $world_overview | jq '.all_worlds.blue' --compact-output | grep $world) ]
then
        curr_colour="blue"
elif [ $(echo $world_overview | jq '.all_worlds.green' --compact-output | grep $world) ]
then
        curr_colour="green"
fi

# Get main world
curr_main=$(echo $world_overview | jq '.worlds.'$curr_colour'')

# Get current position and determine colour next match
if [ $(echo $all_matches | jq '.[] | select(.id == "'$region-$curr_tier'") | .victory_points' --raw-output | sort --key=2 --reverse | head -1 | awk --field-separator ':' '{print $1}' | grep $curr_colour) ]
then
        if [ $curr_tier == 1 ]
        then
                next_tier=$curr_tier
                next_green_main=$curr_main
                colour=$green
        else
                next_tier=$(($curr_tier-1))
                next_red_main=$curr_main
                colour=$red
        fi
elif [ $(echo $all_matches | jq '.[] | select(.id == "'$region-$curr_tier'") | .victory_points' --raw-output | sort --key=2 --reverse | head -2 | awk --field-separator ':' '{print $1}' | grep $curr_colour) ]
then
        next_tier=$curr_tier
        next_blue_main=$curr_main
        colour=$blue
elif [ $(echo $all_matches | jq '.[] | select(.id == "'$region-$curr_tier'") | .victory_points' --raw-output | sort --key=2 --reverse | head -3 | awk --field-separator ':' '{print $1}' |  grep $curr_colour) ]
then
        if [ $curr_tier == $max_tiers ]
        then
                next_tier=$curr_tier
                next_red_main=$curr_main
                colour=$red
        else
                next_tier=$(($curr_tier+1))
                next_green_main=$curr_main
                colour=$green
        fi
fi

next_tier_arr=$(($next_tier-1))

# Get opponents for next match
if [ -z $next_green_main ]
then
        if [ $next_tier == 1 ]
        then
                curr_los_ta=$(echo $all_matches | jq '.[] | select(.id == "'$region-$next_tier'") | .victory_points' --raw-output | sort --key=2 --reverse | head -1 |  awk --field-separator ':' '{print $1}' | sed "s#\"##g" | awk '{print $1}')
                next_green_main=$(echo $all_matches | jq '.[] | select(.id == "'$region-$next_tier'") | .worlds.'$curr_los_ta'')
        else
                curr_los_ta=$(echo $all_matches | jq '.[] | select(.id == "'$region-$(($next_tier-1))'") | .victory_points' --raw-output | sort --key=2 --reverse | head -3 | tail -1 |  awk --field-separator ':' '{print $1}' | sed "s#\"##g" | awk '{print $1}')
                next_green_main=$(echo $all_matches | jq '.[] | select(.id == "'$region-$(($next_tier-1))'") | .worlds.'$curr_los_ta'')
        fi
fi

if [ -z $next_blue_main ]
then
        curr_sec_next=$(echo $all_matches | jq '.[] | select(.id == "'$region-$next_tier'") | .victory_points' --raw-output | sort --key=2 --reverse | head -2 | tail -1 |  awk --field-separator ':' '{print $1}' | sed "s#\"##g" | awk '{print $1}')
        next_blue_main=$(echo $all_matches | jq '.[] | select(.id == "'$region-$next_tier'") | .worlds.'$curr_sec_next'')
fi

if [ -z $next_red_main ]
then
        if [ $next_tier == $max_tiers ]
        then
                curr_win_tb=$(echo $all_matches | jq '.[] | select(.id == "'$region-$next_tier'") | .victory_points' --raw-output | sort --key=2 --reverse | head -3 | tail -1 |  awk --field-separator ':' '{print $1}' | sed "s#\"##g" | awk '{print $1}')
                next_red_main=$(echo $all_matches | jq '.[] | select(.id == "'$region-$next_tier'") | .worlds.'$curr_win_tb'')
        else
                curr_win_tb=$(echo $all_matches | jq '.[] | select(.id == "'$region-$(($next_tier+1))'") | .victory_points' --raw-output | sort --key=2 --reverse | head -1 |  awk --field-separator ':' '{print $1}' | sed "s#\"##g" | awk '{print $1}')
                next_red_main=$(echo $all_matches | jq '.[] | select(.id == "'$region-$(($next_tier+1))'") | .worlds.'$curr_win_tb'')
        fi
fi

# Map world ID to name
world_names=$(curl --silent https://api.guildwars2.com/v2/worlds?ids=$next_green_main,$next_blue_main,$next_red_main)

green_name_main=$(echo $world_names | jq '.[0].name' --raw-output)
blue_name_main=$(echo $world_names | jq '.[1].name' --raw-output)
red_name_main=$(echo $world_names | jq '.[2].name' --raw-output)

# If run on a Friday, don't get next Friday.
if [ $(date +%u) == 5 ]
then
        date=$(date +%F)
        if [ $(grep --fixed-strings --count "$green_name_main$blue_name_main$red_name_main" $match_log) != 1 ]
        # The matches checked on a Friday are not the same as predicted previously
        then
                new_mu_text="**The opponents have changed since last prediction**"
        else
                # The opponents are the same
                exit 0
        fi
else
        date=$(date --date="next Friday" +%F)
fi

echo "$green_name_main$blue_name_main$red_name_main" > $match_log

# Post to Discord
/usr/local/bin/discord.sh --webhook-url="$hook" --color="$colour" --text="$new_mu_text" --title="**$date Reset:**" --description="**Tier $next_tier**\n:green_square: $green_name_main\n:blue_square: $blue_name_main\n:red_square: $red_name_main\n\nMessage goes here." --timestamp --thumbnail="https://url-goes-here.jpg"

exit 0
