import glob
out=[]
tot=0
for p in sorted(glob.glob("entry/src/main/ets/**/*.ets",recursive=True)):
    for i,l in enumerate(open(p,encoding="utf-8").read().split("\n")):
        for j,c in enumerate(l):
            if c!="?": continue
            if j==0: continue
            prev=l[j-1]
            if not ('\u4e00'<=prev<='\u9fff' or '\ue000'<=prev<='\uf8ff'): continue
            q=l[:j].count("'")
            inStr = q%2==1
            out.append((p,i+1,j+1,inStr,l.strip()))
            tot+=1
with open("damage_all.txt","w",encoding="utf-8") as f:
    for p,i,col,ins,line in out:
        f.write(f"{'STR' if ins else 'cmt'} {p}:{i}:{col}\t{line}\n")
print("total",tot,"inString",sum(1 for o in out if o[3]))
