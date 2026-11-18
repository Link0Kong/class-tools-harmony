h=open("head_corpus.txt",encoding="utf-8").read()
for kw in ["去关注宿舍","全部","去勾","第","加载名单","学时","人","个","天"]:
    i=h.find(kw)
    print(kw, i, (h[max(0,i-40):i+40].replace("\n","\\n") if i>=0 else ""))
