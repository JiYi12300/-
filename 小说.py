'''
1.全职法师 入口http://www.126shu.com/15/
2.每个地址的元素,
all_url = .find('dl').find_all('a')
for a in all_url:
    title = a.get_text()
    href = 'http://www.126shu.com' + a['href']
3.div id='content' ---> div class zjtj
4.文件夹和文件名字
5.保存
'''
import os
import requests
from bs4 import BeautifulSoup
url = 'http://www.126shu.com/15/'
#url = input('请输入小说网址: ')
headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/55.0.2883.87 Safari/537.36'}
def request(url):
    html = requests.get(url, headers=headers)
    return html.content.decode('gbk')
all_url = BeautifulSoup(request(url), 'lxml').find('dl').find_all('a')
#文件夹的名字
test = BeautifulSoup(request(url), 'lxml').find('dl').find('dt').get_text().strip().replace('正文', '')
#print(len(all_url))
for a in all_url:
    title = a.get_text()
    #得到每一章节的具体地址
    href = 'http://www.126shu.com' + a['href']
    #文本的具体内容
    extract_text = BeautifulSoup(request(href), 'lxml').find('div', id='content')
    [s.extract() for s in extract_text('div', class_='zjtj')] 
    [s.extract() for s in extract_text('div', class_='zjxs')]
    ever_text = extract_text.get_text().replace('\xa0'*4, '\r\n')
    name = title.strip().replace('?', '')
    path = os.path.join('C:\\小说', test)
    isExist = os.path.exists(path)
    if not isExist:
        print('创建文件夹: %s' % test)
        os.makedirs(path)
        os.chdir(path)
        with open(name+ '.txt', 'w') as f:
            print('这在写入 %s ' % name)
            f.write(ever_text)
    else:
        os.chdir(path)
        if os.path.isfile(name+'.txt'):
            print('跳过 %s' % name)
        else:
            with open(name+ '.txt', 'w') as f:
                print('这在写入 %s ' % name)
                f.write(ever_text)
