import glob,re,subprocess
pat=re.compile(r"[\u4e00-\u9fff\ue000-\uf8ff]\?(?=[;,)\]}'\"]|$)")
def rec(l): return l.encode("gb18030","replace").decode("utf-8","replace")
# build HEAD corpus
tracked=subprocess.run(["git","ls-files","entry/src"],capture_output=True,text=True,encoding="utf-8").stdout.split()
head=""
for t in tracked:
    if t.endswith((".ets",".ts")):
        head+=subprocess.run(["git","show","HEAD:"+t],capture_output=True).stdout.decode("utf-8","replace")
print("HEAD corpus chars:",len(head))
open("head_corpus.txt","w",encoding="utf-8").write(head)
for p in sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True)):
    lines=open(p,encoding="utf-8").read().split("\n")
    for i,l in enumerate(lines):
        if pat.search(l):
            r=rec(l)
            print(f"{p}:{i+1}")
            print("  CUR:",l.strip().encode("unicode_escape").decode())
            print("  REC:",r.strip().encode("unicode_escape").decode())
