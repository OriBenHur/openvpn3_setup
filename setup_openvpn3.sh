#!/usr/bin/env bash

if [[ "$EUID" -eq 0 ]]; then
	echo "This script is not meant to be tun as root!"
	exit 1
fi

function install_openvpn3() {
	set -euo pipefail
	sudo apt install apt-transport-https -y
	sudo curl -fsSL https://swupdate.openvpn.net/repos/openvpn-repo-pkg-key.pub | sudo apt-key add -
	curl -fsSL "https://swupdate.openvpn.net/community/openvpn3/repos/openvpn3-$(lsb_release -cs).list" | sed 's/\<deb\>/& [arch=amd64]/' | sudo tee /etc/apt/sources.list.d/openvpn3.list >/dev/null
	sudo apt update
	sudo apt install openvpn3 -y
	echo
	echo
	set +euo pipefail
}

function import_config() {
	read -r -e -p 'Path to config.ovpn: ' ovpn
	if [[ ! -f "$(eval echo "${ovpn}")" ]]; then
		echo -e '\033[31mNo such file\033[0m'
		exit 1
	fi
	echo
	echo -e '\033[33mImporting config file\033[0m'
	openvpn3 config-import --config "$(eval echo "${ovpn}")" --name "${config}" --persistent
}

function generate_config() {
	local config="${1}"
	tee -a ~/.bash_aliases >/dev/null <<'EOM'
##DONT_REMOVE##
    function vpn(){
        local help_options=("h" "help" "--help" "-h")
        local valid_options=("start" "stop" "stop-all" "pause" "resume" "restart" "log" "status" "list" "clean")
        local option="${1:-help}"
        local config="${2}"
        if [[ " ${help_options[@]} " =~ " ${option} " ]] || [[ ! " ${valid_options[@]} " =~ " ${option} "  ]]; then
            [[ !  " ${help_options[@]} " =~ " ${option} " ]] && echo -e "\033[31m${option} is not a valid option\033[0m\n"
            echo  -e "Usage: ${0} option [config]

Options:
    start [config]      connect to vpn
    stop [config]       disconnect from the vpn
    stop-all            disconnect from all active vpn sessions
    pause [config]      pause the vpn session
    resume [config]     resume the vpn session
    restart [config]    restart the vpn session
    log [config]        get session logs
    status [config]     get vpn sessions status
    list                list all vpn sessions
    clean               cleans inactive vpn sessions from buffer

Examples:
    vpn start john_doe  will use john_doe config to connect
    vpn start           will use the default config
    vpn stop john_doe   will disconnect the session associated with the john_doe config
    vpn stop            will disconnect the session associated with the default config"


        elif [[ "${option}" == "start" ]]; then
                command openvpn3 session-start --config ${config:-<USER_CONFIG_NAME>}
        elif [[ "${option}" == "stop"  ]]; then
                command openvpn3 session-manage --disconnect --config ${config:-<USER_CONFIG_NAME>}
        elif [[ "${option}" == "stop-all" ]]; then
                ACTIVE_SESSIONS=$(openvpn3 sessions-list | grep -i 'path' | awk '{p=index($0, ":");print $2}')
                echo $ACTIVE_SESSIONS
                for instance in $ACTIVE_SESSIONS; do
                    openvpn3 session-manage --disconnect --session-path ${instance}
                done
        elif [[ "${option}" == "pause" ]]; then
                command openvpn3 session-manage --pause --config ${config:-<USER_CONFIG_NAME>}
        elif [[ "${option}" == "resume" ]]; then
                command openvpn3 session-manage --resume --config ${config:-<USER_CONFIG_NAME>}
        elif [[ "${option}" == "log" ]]; then
                command openvpn3 log --log-level 6 --config ${config:-<USER_CONFIG_NAME>}
        elif [[ "${option}" == "restart" ]]; then
                command openvpn3 session-manage --restart --config ${config:-<USER_CONFIG_NAME>}
        elif [[ "${option}" == "status" ]]; then
                command openvpn3 session-stats --config ${config:-<USER_CONFIG_NAME>}
        elif [[ "${option}" == list ]]; then
                command openvpn3 sessions-list
        elif [[ "${option}" == "clean" ]]; then
                openvpn3 session-manage --cleanup
        fi
}
##DONT_REMOVE##
EOM
	sed -i "s/<USER_CONFIG_NAME>/${config}/g" ~/.bash_aliases
}

function openvpn_config_setup() {
	local count=0
	while [[ -z "${config}" ]]; do
		read -r -e -p 'Name your config: ' config
		[[ -z "${config}" ]] && echo "Config must be non empty, try again"
	done

	if openvpn3 config-show --config "${config}" >/dev/null 2>&1; then
		echo -e "\033[34mThere is already a config with that name overwrite it?\033[0m"
		select yn in "Yes" "No"; do
			case $yn in
			"Yes")
				openvpn3 config-remove --config "${config}" --force >/dev/null
				import_config
				break
				;;
			"No")
				break
				;;
			esac
		done
	else
		import_config
	fi

	unset yn
	if grep '##DONT_REMOVE##' ~/.bash_aliases >/dev/null; then
		echo
		echo -e "\033[34mFunction already exist, overwrite it?\033[0m"
		select yn in "Yes" "No"; do
			case $yn in
			"Yes")
				sed -i '/##DONT_REMOVE##/,/##DONT_REMOVE##/d' ~/.bash_aliases
				generate_config "${config}"
				echo
				echo -e "\033[33mThe function was updated\033[0m"
				break
				;;
			"No")
				echo
				echo -e "\033[34mFunction was left as is\033[0m"
				((count = count + 1))
				break
				;;
			esac
		done
	else
		echo
		echo -e "\033[33mCreating vpn function\033[0m"
		generate_config "${config}"
	fi

	if [[ ! -f /etc/bash_completion.d/vpn ]]; then
		echo
		echo -e "\033[33mCreating bash completion\033[0m"
		sudo tee /etc/bash_completion.d/vpn <<<'complete -W "help start stop stop-all pause resume restart log status list clean" vpn' >/dev/null
	else
		echo -e "\033[31mBASH completion already exist will not overwrite\033[0m"
		((count = count + 1))
	fi
	if [[ ${count} -eq 2 ]]; then
		echo -e "\033[31mNothing to do exiting\033[0m"
		exit 0
	else
		echo
		echo -e "\033[32m#######################################################################################################"
		echo -e "                           Please Run '"exec "$(basename "$SHELL")""' to complete the operation"
		echo -e "    Then you can now use vpn {help|start|stop|stop-all|pause|resume|log|restart|status|list|clean} [config]"
		echo -e "#######################################################################################################\033[0m"
		echo
	fi
}

function openvpn_cleanup() {
	unset yn
	local config
	config=$(grep -oP '(?<=config\s\$\{config:-)\w+' ~/.bash_aliases | head -1)
	sed -i '/##DONT_REMOVE##/,/##DONT_REMOVE##/d' ~/.bash_aliases
	sudo rm /etc/bash_completion.d/vpn -f
	echo -e "\033[34mRemove saved openvpn config?\033[0m"
	select yn in "Yes" "No"; do
		case $yn in
		"Yes")
			if [[ -z "${config}" ]]; then
				configs=()
				while IFS='' read -r line; do configs+=("$line"); done < <(openvpn3 configs-list | sed -e '/-/d' -e '/\//d' -e '/\(Configuration path\|Imported\|Name\)/d' -e '/^$/d' | awk 'NF{NF-=1};1' | sed '/\s/d')

				case "${#configs[@]}" in
				0)
					echo -e "\033[31mNo configuration to remove\033[0m"
					break 2
					;;
				1)
					openvpn3 config-remove --config "${configs[0]}" --force
					break 2
					;;
				*)
					echo
					echo -e "\033[34mCan't identify config automatically pleas pick the right one\033[0m"
					select conf in "${configs[@]}"; do
						openvpn3 config-remove --config "${conf}" --force
						break 2
					done
					;;
				esac
			else
				openvpn3 config-remove --config "${config}" --force
				break 2
			fi
			;;
		"No")
			break 2
			;;
		esac
	done
	echo
	echo -e "\033[32mPlease Run '"exec "$(basename "$SHELL")""' to complete the operation\033[0m"
	echo
}

args=("$@")
if [[ "${#args[@]}" -le 0 ]]; then
	echo "Available switches are '[-i|--install] | [-u|--uninstall]'"
	exit 0
fi

case "${args[0]}" in
"-i" | "--install")
	if ! dpkg -l | grep openvpn3 >/dev/null; then
		install_openvpn3
	fi
	shift
	openvpn_config_setup
	;;
"-u" | "--uninstall")
	openvpn_cleanup
	;;
*)
	echo "Available switches are '[-i|--install] | [-u|--uninstall]'"
	;;
esac
