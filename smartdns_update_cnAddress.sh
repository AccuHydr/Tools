#下载三个最新列表合并到cn_new.conf
curl  "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/direct-list.txt"  >> /etc/smartdns/cn_new.conf
curl  "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/apple-cn.txt"    >> /etc/smartdns/cn_new.conf
curl  "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/google-cn.txt"   >> /etc/smartdns/cn_new.conf

#去除full regexp并指定cn组解析
sed "s/^full://g;/^regexp:.*$/d;s/^/nameserver \//g;s/$/\/cn/g" -i /etc/smartdns/cn_new.conf

#覆盖旧文件
mv /etc/smartdns/cn_new.conf /etc/smartdns/domain-set/cn.conf -f


