import subprocess,glob
enc=subprocess.run(["powershell","-NoProfile","-Command","$e=[System.Text.Encoding]::GetEncoding(936);$b=[System.IO.File]::ReadAllBytes('entry/src/main/ets/ui/tools/RosterScreen.ets');$s=[System.Text.Encoding]::UTF8.GetString($b);[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$e.GetString($e.GetBytes($s))"],capture_output=True)
print(enc.returncode, len(enc.stdout))
