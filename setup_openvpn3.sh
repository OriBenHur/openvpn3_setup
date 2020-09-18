#!/usr/bin/env bash

function install_openvpn3() {
    sudo apt install apt-transport-https -y
    sudo curl -fsSL https://swupdate.openvpn.net/repos/openvpn-repo-pkg-key.pub | sudo apt-key add -
    curl -fsSL https://swupdate.openvpn.net/community/openvpn3/repos/openvpn3-$(lsb_release -cs).list | sed 's/deb/deb [arch=amd64]/g' | sudo tee /etc/apt/sources.list.d/openvpn3.list > /dev/null
    sudo apt update
    sudo apt install openvpn3 -y
    echo 
    echo
}

function import_config()
{
    read -e -p 'Path to config.ovpn: ' ovpn
    if [[ ! -f "$(eval echo ${ovpn})" ]]; then 
        echo -e '\033[31mNo such file\033[0m'
        exit 1
    fi
    echo
    echo -e '\033[33mImporting config file\033[0m'
    openvpn3 config-import --config "$(eval echo ${ovpn})" --name ${config} --persistent
    echo
}
function openvpn_config_setup(){
    local count=0
    read -e -p 'Name your config: ' config
    if openvpn3 config-show --config "${config}" > /dev/null 2>&1; then
        echo -e "\033[34mThere is already a config with that name overwrite it?\033[0m"
            select yn in "Yes" "No"; do
            case $yn in
            "Yes" )
                openvpn3 config-remove --config "${config}" --force > /dev/null
                import_config
                break
                ;;
            "No" )
                break
                ;;
            esac
        done
    else
        import_config
    fi

    unset yn
    if grep '##DONT_REMOVE##' ~/.bash_aliases > /dev/null; then
        echo -e "\033[34mFunction already exist, overwrite it?\033[0m"
        select yn in "Yes" "No"; do
            case $yn in
            "Yes" )
                old_conf=$(grep -oP '(?<=config\s)\w+' ~/.bash_aliases | head -1)
                if [[ "${old_conf}" == "${config}" ]];then 
                     echo -e  "\033[33mExisting config is identical to new one, aborting\033[0m"
                     break
                     ;;
                fi
                sed -i "s/${old_conf}/${config}/g" ~/.bash_aliases
                echo -e "\033[33mThe function was updated\033[0m"
                break
                ;;
            "No" )
                echo -e "\033[34mFunction was left as is\033[0m"
                ((count=count+1))
                echo
                break
                ;;
            esac
        done
    else
        echo -e "\033[33mCreating vpn function\033[0m"
        echo
        tee -a ~/.bash_aliases > /dev/null << 'EOM'
##DONT_REMOVE##
function vpn(){
        local option="${1}"
        if [[ -z "${option}" ]]  || [[ "${option}" == "help" ]] || [[ "${option}" == "h" ]] || [[ "${option}" == "-h" ]] ||  [[ "${option}" == "--help" ]]; then
            echo  -e "${0} [arg]
con     connect to to vpn
disco   disconnect from the vpn
pause   pause the vpn session
resume  resume the vpn session
restart restart the vpn session
log     get sssion logs
status  get vpn sessions status
list    list all vpn sessions
clean   cleans inactive vpn sessions from buffer"

        elif [[ "${option}" == "con" ]]; then
                command openvpn3 session-start --config <USER_CONFIG_NAME>
        elif [[ "${option}" == "disco"  ]]; then
                command openvpn3 session-manage --disconnect --config <USER_CONFIG_NAME>
        elif [[ "${option}" == "pause" ]]; then
                command openvpn3 session-manage --pause --config <USER_CONFIG_NAME>
        elif [[ "${option}" == "resume" ]]; then
                command openvpn3 session-manage --resume --config <USER_CONFIG_NAME>
        elif [[ "${option}" == "log" ]]; then
                command openvpn3 log --log-level 6 --config <USER_CONFIG_NAME>
        elif [[ "${option}" == "restart" ]]; then
                command openvpn3 session-manage --restart --config <USER_CONFIG_NAME>
        elif [[ "${option}" == "status" ]]; then
                command openvpn3 session-stats --config <USER_CONFIG_NAME>
        elif [[ "${option}" == list ]]; then
                command openvpn3 sessions-list
        elif [[ "${option}" == "clean" ]]; then
                openvpn3 session-manage --cleanup
        fi
}
##DONT_REMOVE##
EOM
        sed -i "s/<USER_CONFIG_NAME>/${config}/g" ~/.bash_aliases
    fi

    if [[ ! -f /etc/bash_completion.d/vpn ]];then 
        echo -e "\033[33mCreating bash complition\033[0m"
        sudo tee /etc/bash_completion.d/vpn <<< 'complete -W "help con disco pause resume restart log status list clean" vpn' > /dev/null
        echo
    else
        echo -e "\033[31mBASH complition already exist will not overwrite\033[0m"
        echo
        ((count=count+1))
    fi
    if [[ ${count} -eq 2 ]]; then
        echo -e "\033[31mNothing to do exiting\033[0m"
        exit 0
    else
        echo 
        echo -e "\033[32m##############################################################################################"
        echo -e "#                       Please Run '"exec $(basename $SHELL)"' to complete the operation                      #"
        echo -e "#    Then you can now use vpn [help|con|disco|pause|resume|log|restart|status|list|clean]    #"
        echo -e "##############################################################################################\033[0m"
        echo
    fi
}

function openvpn_cleanup(){
    local config=$(grep -oP '(?<=config\s)\w+' ~/.bash_aliases | head -1)
    sed -i '/##DONT_REMOVE##/,/##DONT_REMOVE##/d' ~/.bash_aliases
    sudo rm /etc/bash_completion.d/vpn -f
    echo -e "\033[34mRemove saved openvpn config?\033[0m"
    select yn in "Yes" "No"; do
    case $yn in
            "Yes" )
                if [[ -z "${config}" ]]; then 
                    configs=($(openvpn3 configs-list | sed -e '/-/d' -e '/\//d' -e '/\(Configuration path\|Imported\|Name\)/d' -e '/^$/d' | awk 'NF{NF-=1};1' | sed '/\s/d'))
                    case "${#configs[@]}" in
                    0)
                        echo -e "\033[31mNo configuration to remove\033[0m"
                        break 2
                        ;;
                    1)
                        openvpn3 config-remove --config ${configs[0]} --force
                        break 2
                        ;;
                    *)
                        echo
                        echo -e "\033[34mCan't idenify config automaticlly pleas pick the right one\033[0m"
                        select conf in "${configs[@]}"; do
                            openvpn3 config-remove --config ${conf} --force
                            break 2
                        done
                        ;;
                    esac
                else
                    openvpn3 config-remove --config ${config} --force
                    break 2
                fi
                ;;
            "No" )
                break
                ;;
        esac
    done
    echo
    echo -e "\033[32mPlease Run '"exec $(basename $SHELL)"' to complete the operation\033[0m"
    echo

}

args=("$@")
if [[ "${#args[@]}" -le 0 ]];then
    echo "Available switches are '[-i|--install] | [-u|--uninstall]'"
    exit 0
fi

case "${args[1]}" in
    "-i"|"--install")
        if ! dpkg -l | grep openvpn3 > /dev/null; then 
            install_openvpn3
        fi
        shift
        openvpn_config_setup
        ;;
    "-u"|"--uninstall")
        openvpn_cleanup
        ;;
    *)
        echo "Available switches are '[-i|--install] | [-u|--uninstall]'"
esac
