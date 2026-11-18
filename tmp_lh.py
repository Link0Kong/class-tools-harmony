import re
p=r"C:\Users\Ko_Li\AppData\Local\Huawei\DevEcoStudio26.0\LocalHistory\changes.storageData"
b=open(p,"rb").read()
for kw in ["首页","班级","工具箱","MONET","heroCard","powerQ"]:
    k=kw.encode("utf-8")
    print(kw, b.count(k))
