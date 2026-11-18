import subprocess,glob,collections
tracked=subprocess.run(["git","ls-files","entry/src"],capture_output=True,text=True,encoding="utf-8").stdout.split()
common=collections.Counter()
for t in tracked:
    if not t.endswith((".ets",".ts")): continue
    try: s=subprocess.run(["git","show","HEAD:"+t],capture_output=True).stdout.decode("utf-8")
    except Exception: continue
    for c in s:
        if '\u4e00'<=c<='\u9fff': common[c]+=1
print("distinct chars in HEAD",len(common))
open("headchars.txt","w",encoding="utf-8").write("".join(sorted(common)))
