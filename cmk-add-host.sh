#!/bin/bash
#Author: gyang
#Purpose: Add a host to check_mk
#Requires: 
#  curl for posting
#  jq for parsing return output from check_mkk
#

#Required Variables
#check_mk automation user/secret and check_mk server
#this was created for use with OMD
#note: This is not a regular user/password
autouser=automation_user
secret=automation_secret
checkmk=localhost
omd_site=mysite
#default folder is the WATO home
folder="\/"

usage() {
echo "
Usage: $0 -h host 
       [-a] [-z alias] [-f foldername] 
       [-t tag1_key:tag1_value,tag2_key:tag2_value,tag3_key:tag3_value]

    -h    host
    -a    Optional. Default is yes. Change to no if you want to just inventory the host. 
    -z    Optional. Specify the alias name
    -f    Optional. Specify the name of the check_mk folder the
	  host is to be added to
    -t    Optiional. Specify the tag(s)
    -?    This message
"
}

while getopts h:a:z:f:t:? ARG; do
	case $ARG in
		h)
			hostname=$OPTARG
			;;
                a)
                        addhost=$OPTARG
                        ;;
                z)
                        alias=$OPTARG
                        ;;
		f)
			folder=$OPTARG
			;;
                t)
                        tags=$OPTARG
                        ;;
		?)
			usage
			exit
			;;
	esac
done

#Make sure we get a hostname to add
if [ ! "${hostname}" ]; then
  echo "hostname is required" 1>&2
  usage
  exit 1
else
#Make sure the hostname resolves to some ipv4 address
  ip_result=$(host ${hostname} |grep "has address" | head -1 | awk '{print $4}')
  if [[ ${ip_result} ]];then
    c_ipaddress="\"ipaddress\": \"$ip_result\"}"
    c_hostname=",\"hostname\": \"${hostname}\","
  else
    echo "${hostname} doesn't appear to have an ipv4 address, exiting"
    usage
    exit 1
  fi
fi

#The web api requires a folder path
  c_folder="\"folder\": \"${folder}\""

#Add an alias?
if [[ "${alias}" ]];then
c_alias="\"alias\": \"${alias}\","
fi
#Add tags?
if [[ "${tags}" ]];then
declare -a arraytags=($(echo ${tags} | sed -e 's/,/ /'g))

for i in "${arraytags[@]}"; do
c_tags="${tag} $(echo $i | awk -F : '{print "\""$1"\""": ""\""$2"\","}')"
tag=${c_tags}
done
fi

#Post to check_mk
post_to_checkmk()
{
case $1 in
  addhost)
echo "adding host ${hostname}"
curl_result=$(curl -s "http://${checkmk}/${omd_site}/check_mk/webapi.py?action=add_host&_username=${autouser}&_secret=${secret}" -d "request={\"attributes\":{${c_alias} ${c_tags} ${c_ipaddress} ${c_hostname} ${c_folder}}")
  ;;
  inventoryhost)
echo "inventory host ${hostname}"
curl_result=$(curl -s "http://${checkmk}/${omd_site}/check_mk/webapi.py?action=discover_services&_username=${autouser}&_secret=${secret}&mode=refresh" -d "request={$(echo ${c_hostname} | sed -e 's/,//g')}")
  ;;
esac

export result_code=$(echo ${curl_result}|jq .| jq '.result_code')
export result=$(echo ${curl_result}|jq .| jq '.result')
}

if [[ "${addhost}" == "no" ]];then
  post_to_checkmk inventoryhost
  else
  post_to_checkmk addhost
  post_to_checkmk inventoryhost
fi

if [[ "${result}" == "null" ]];then
  echo Completed!
  exit ${result_code}
fi
echo "Message: ${result}"
exit ${result_code}
