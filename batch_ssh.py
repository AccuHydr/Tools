import paramiko
import os
import yaml

from concurrent.futures import ThreadPoolExecutor, as_completed

def initialize_config():
    """
    检测是否存在 config.yaml 文件。
    如果不存在，则创建一个默认的配置文件并退出程序。
    如果存在，则读取配置文件内容。
    """
    config_path = "config.yaml"

    if not os.path.exists(config_path):
        # 创建默认配置文件
        default_config = {
            "user": "root",
            "servers": [
                {"host": "127.0.0.1", "port": 11451},
                {"host": "localhost", "port": 41919}
            ],
            "password_or_phrase": "",
            "private_key": "private"
        }

        with open(config_path, "w") as f:
            yaml.dump(default_config, f)

        print(f"配置文件 {config_path} 不存在，已创建默认配置文件。请修改后重新运行程序。")
        exit(1)

    # 读取配置文件
    with open(config_path, "r") as f:
        config = yaml.safe_load(f)

    return config

def scheduler_ssh_interactive(servers, username, private_key_path="", password="",private_key_password=""):
    """
    调度器：同时连接所有服务器，统一分发命令并等待所有服务器响应。

    :param servers: 服务器列表，每个服务器是一个字典，包含 'host' 和 'port'。
    """

    # 加载私钥
    if private_key_path:
        private_key = paramiko.ECDSAKey.from_private_key_file(private_key_path, password=private_key_password)

    # 存储所有连接
    connections = {}
    
    print("正在连接到所有服务器...")
    
    # 连接到所有服务器
    for server in servers:
        host = server['host']
        port = server.get('port', 22)
        
        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            if private_key_path:
                ssh.connect(hostname=host, port=port, username=username, pkey=private_key)
            else:
                ssh.connect(hostname=host, port=port, username=username, password=password)
            channel = ssh.invoke_shell()
            connections[host] = {'ssh': ssh, 'channel': channel}
            print(f"已连接到 {host}")
        except Exception as e:
            print(f"连接到 {host} 时出错: {e}")
    
    print(f"成功连接到 {len(connections)} 台服务器")
    print("现在可以输入命令，命令将分发到所有服务器")
    print("输入 'quit' 退出程序")
    
    try:
        while True:
            # 获取用户输入
            command = input("\n命令> ").strip()
            
            if command.lower() == 'quit':
                break
                
            if not command:
                continue
            
            print(f"\n正在分发命令到 {len(connections)} 台服务器...")
            
            # 分发命令到所有服务器
            for host, conn in connections.items():
                try:
                    conn['channel'].send((command + "\n").encode())
                except Exception as e:
                    print(f"向 {host} 发送命令时出错: {e}")
            
            # 等待所有服务器响应
            import time
            time.sleep(1)  # 给服务器一些时间处理命令
            
            all_outputs = {}
            for host, conn in connections.items():
                try:
                    if conn['channel'].recv_ready():
                        output = conn['channel'].recv(4096).decode()
                        all_outputs[host] = output
                    else:
                        all_outputs[host] = "无响应"
                except Exception as e:
                    all_outputs[host] = f"获取输出时出错: {e}"
            
            # 显示所有服务器的输出
            print("\n=== 所有服务器响应 ===")
            for host, output in all_outputs.items():
                print(f"\n--- {host} ---")
                print(output)
                print("-" * 50)
            
    except KeyboardInterrupt:
        print("\n用户中断操作")
    
    finally:
        # 关闭所有连接
        print("正在关闭所有连接...")
        for host, conn in connections.items():
            try:
                conn['channel'].close()
                conn['ssh'].close()
                print(f"已关闭与 {host} 的连接")
            except Exception as e:
                print(f"关闭与 {host} 的连接时出错: {e}")

# 在主程序开始时调用初始化函数
if __name__ == "__main__":
    config = initialize_config()

    user = config["user"]
    servers = config["servers"]
    password_or_phrase = config["password_or_phrase"]
    private_key = config["private_key"]

    # 调度器进行交互式 SSH
    scheduler_ssh_interactive(servers, username=user, private_key_path=private_key, private_key_password=password_or_phrase)
