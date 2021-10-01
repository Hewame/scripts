#!/usr/bin/env bash
# Author : Hewa S.
# Require Bash V. 4.0 and/or higher
# Disclaimer ##################################################################
# This Script is for Educational Purposes only, Use at Your Own Risk
# WARNING! Do not rely on this script, always expect undesirable results.
###############################################################################

####### Check Bash Version
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
    :
else
    printf "oops! unable to run, require Bash 4.0 or higher \n"
    exit 1
fi

####### Check Dependencies
utils=("dig" "whois" "telnet" "host")
for tools in ${utils[@]}; do
    type "$tools" >/dev/null 2>&1 || { echo >&2 "Error: $tools is not found. You need to install $tools"; exit 1; }
done


usage_info () {
    echo "
USAGE:
    $0 [FLAG] [SELECTION]

    -d|--domain     domain name
                    accepts a single domain 

    -f|--file       read domains from file
                    domains should be separated by a space or a new line

    -h|--help|*     print this message
                    example: $0 -d facebook.com
                    example: $0 -f socialnet.txt
    "
}

####### Get Destination IP from Hostname TLD/FQDN
declare -a DIPv4 # an empty array for Destination IPv4 
declare -a DIPv6 # an empty array for Destination IPv6 

tldtoip (){
    printf "======= %s \n" "$2" | tr '[:lower:]' '[:upper:]'
    readarray -t DIPv4 < <(dig +short @8.8.8.8 A "$2" | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
    printf "%s\n%s\n" "Found ${#DIPv4[@]} IPv4:" "${DIPv4[@]}"
    readarray -t DIPv6 < <(dig +short @8.8.8.8 AAAA "$2" | grep -E '^[[:xdigit:]]')
    printf "%s\n%s\n" "Found ${#DIPv6[@]} IPv6:" "${DIPv6[@]}"
    return
}

####### Positional Parameters: Check Arguments
check_args () {
    if (( $# == 2 )); then
        case $1 in
            -d|--domain) check_hostname "$@" ;;
            -f|--file)
                if [ -e "$2" ]; then
                    multigen "$@"
                    exit 0
                else
                    printf "can't open %s no such file \n" "$2"
                    exit 1
                fi
                ;;
            *) usage_info
            exit 1 ;;
        esac
    else
       usage_info 
       exit 1
    fi
    return
}

####### Positional Parameters: Validate Hostname
check_hostname () {
    if host "$2" > /dev/null 2>&1 ; then
        :
    else
        printf "Error: %s is not valid Hostname, check your Network! \n" "$2"
        exit 1
    fi
}

####### Getting ASN from IP #######
getASNfromIP () {
    # Give a priority to IPv4 
    if (( ! "${#DIPv4}" == 0 )); then
        DIP=("${DIPv4[@]}")
    elif (( ! "${#DIPv6}" == 0 )); then
        DIP=("${DIPv6[@]}")
    else
        printf "Found Nothing, check your network or internet connection \n"
        exit 1
    fi

    printf "======= Getting ASN from IP Addresses \n"
    declare -a TASN # Temporary ASN expect Duplicate items.

        for items in "${DIP[@]}"; do
        readarray -t -O "${#TASN[@]}" TASN < <(whois -h whois.radb.net "$items" | awk '$1 == "origin:" {print $2}' | grep -iE '^AS[1-9]{1,5}')
#        printf "%s%s\n" "$items has the following ASN: " "${TASN[*]}" # Warning! This is only for debug, comment/remove it later
        done

    # unique ASN
    ASN=($(tr ' ' '\n' <<< "${TASN[@]}" | sort -u | tr '\n' ' '))
    printf "%s%s\n" "Found ${#ASN[@]} ASN: " "${ASN[*]}"
    return
}

####### Generate IP for a single domain entry #######
        # Note from radb.net: If you plan on making a large number of queries please invoke a persistent tcp/ip session.
        # This is done by telneting directly to whois.radb.net and issuing the !! command.
        # This will spare our server having to establish and teardown connections for every query.
generateIP () {
    printf "======= Starting Telnet Session \n"
    printf "Please wait! \n"
    for items in ${ASN[*]}; do
        printf "Getting ip routes from $items \n" #debug
        # use Telnet to query via radb.net
        # Automating Telnet session in Bash is kinda suck! TODO: use another method
        ( sleep 5; echo '!g'"$items" ; sleep 5; ) | telnet -E whois.radb.net 43 2> /dev/null | tee | awk 'NR==5' | tr ' ' '\n' >> ."$2".v4dup
#        whois -h whois.radb.net -- "-K -i origin $items" | awk '$1 == "route:" {print $2}' >> ."$2.v4dup"
        sleep 5
#        whois -h whois.radb.net -- "-K -i origin $items" | awk '$1 == "route6:" {print $2}' >> ."$2.v6dup"
        ( sleep 5; echo '!6'"$items" ; sleep 5; ) | telnet -E whois.radb.net 43 2> /dev/null | tee | awk 'NR==5' | tr ' ' '\n' >> ."$2".v6dup
    done
    printf "======= Closing Telnet Session \n"
}


final_result () {
    printf "======= Cleanup, Removing Duplicate Lines: %s \n" "$2"
    sort -u ."$2.v4dup" > "$2.ipv4"
    sort -u ."$2.v6dup" > "$2.ipv6"
    rm ."$2.v4dup" ."$2.v6dup"

    printf "Found %s unique IPv4 routes \n" "$(wc -l "$2.ipv4")"
    printf "Found %s unique IPv6 routes \n" "$(wc -l "$2.ipv6")"
    printf "======= Done \n"
    return
}

####### Generate IP for multiple entry from File #######
multigen () {
    local FILE="$2"
    local checked_domains=()

    for hosts in $(cat "$FILE"); do
        printf "Checking Hostname: %s \n" "$hosts"
        check_hostname "" "$hosts"
        checked_domains+=("$hosts")
    done
    
    printf "%s\n" "Checked ${#checked_domains[@]} Hosts successfully"

    for domains in ${checked_domains[@]} ; do
        tldtoip "" "$domains"
        getASNfromIP
        generateIP "" "$domains"
        final_result "" "$domains"
    done

}

# This is for a single domain name
check_args "$@"
tldtoip "$@"
getASNfromIP
generateIP "$@"
final_result "$@"
