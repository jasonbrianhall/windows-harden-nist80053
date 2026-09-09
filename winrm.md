# Set your network to private in windows settings

winrm quickconfig -q
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'   # or set up HTTPS w/ a cert
New-NetFirewallRule -Name WinRM-HTTP -DisplayName "WinRM HTTP" -Protocol TCP -LocalPort 5985 -Action Allow

net user administrator /active:yes
net user administrator Changeme123!
