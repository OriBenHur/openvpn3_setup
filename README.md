## What is the purpose of this tool?


It aims to ease the installation of the openvpn3 linux client.  
It also tries to provide simpler cli for basic commands where the original cli is a bit non-intuitive.

Original  | New
------------- | -------------
openvpn3 session-start --config \<CONFIG\>  | vpn start [config]
command openvpn3 session-manage --disconnect --config \<CONFIG\> | vpn stop [config]
openvpn3 session-manage --pause --config \<CONFIG\> | vpn pause [config]
openvpn3 session-manage --resume --config \<CONFIG\> |  vpn resume [config]
openvpn3 session-manage --restart --config \<CONFIG\> | vpn restart [config]
openvpn3 session-stats --config \<CONFIG\> | cpn status [config]
openvpn3 log --log-level 6 --config \<CONFIG\> | vpn log [config]
openvpn3 sessions-list |  vpn list
openvpn3 session-manage --cleanup | vpn clean





   