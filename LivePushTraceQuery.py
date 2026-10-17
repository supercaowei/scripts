#!/usr/bin/env python3

import requests
import json
import urllib.parse
from datetime import datetime, timedelta
import argparse
import csv
import sys
import time
from typing import List, Dict, Any, Optional, Union
import os

FULL_RECORD_FIELD = '详情'
FIXED_OUTPUT_FIELDS = ('timestamp', 'event_key')


def parse_url_params(url: str) -> Dict[str, Any]:
    """解析URL中的查询参数"""
    parsed = urllib.parse.urlparse(url)
    
    # 尝试从fragment和query中解析参数
    if parsed.fragment:
        params = urllib.parse.parse_qs(parsed.fragment)
    elif parsed.query:
        params = urllib.parse.parse_qs(parsed.query)
    else:
        params = {}
    
    result = {
        'End': int(params.get('End', [0])[0]),
        'Filter': json.loads(params.get('Filter', ['[]'])[0]) if params.get('Filter') else [],
        'Interval': params.get('Interval', ['auto'])[0],
        'Namespace': params.get('Namespace', [''])[0],
        'Order': params.get('Order', [''])[0],
        'OrderBy': params.get('OrderBy', [''])[0],
        'QueryString': params.get('QueryString', [''])[0],
        'Start': int(params.get('Start', [0])[0]),
        'fieldList': params.get('fieldList', [''])[0].split(',') if params.get('fieldList') else []
    }
    return result

def build_jsonrpc_request(namespace: str, start_ms: int, end_ms: int, 
                         filters: List[Dict], limit: int = 200, offset: int = 0) -> List:
    """构建JSON-RPC格式的请求"""
    api_path = "/api/liveAlarmNew/index.js"
    method_name = "GetFieldList"
    
    request_data = [
        api_path,
        ["default", method_name],
        [{
            "Namespace": namespace,
            "Interval": "auto",
            "Start": start_ms,
            "End": end_ms,
            "Filter": filters,
            "Limit": limit,
            "Offset": offset
        }, "zh"]
    ]
    
    return request_data

def query_logs_jsonrpc(cookie_connect_sid: str, request_data: List, 
                      url: str = "") -> Optional[Dict]:
    """发送JSON-RPC格式的日志查询请求"""
    headers = {
        'accept': '*/*',
        'accept-language': 'en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7',
        'content-type': 'application/json',
        'cookie': f'connect.sid={cookie_connect_sid}',
        'sec-ch-ua': '" Not A;Brand";v="99", "Chromium";v="100", "Google Chrome";v="100"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"macOS"',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-origin',
        'user-agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36',
        'x-require-node': 'true'
    }
    
    try:
        response = requests.post(url, json=request_data, headers=headers, timeout=30)
        print(f"响应状态码: {response.status_code}", file=sys.stderr)
        
        if response.status_code != 200:
            print(f"请求失败: {response.status_code}", file=sys.stderr)
            print(f"响应内容: {response.text[:200]}...", file=sys.stderr)
            return None
        
        return response.json()
            
    except requests.exceptions.RequestException as e:
        print(f"请求异常: {e}", file=sys.stderr)
        return None
    except json.JSONDecodeError as e:
        print(f"JSON解析失败: {e}", file=sys.stderr)
        if 'response' in locals():
            print(f"原始响应: {response.text[:500]}...", file=sys.stderr)
        return None

def extract_data_from_response(response_json: List) -> List[Dict]:
    """从响应JSON中提取Result.List数据"""
    if not response_json or len(response_json) < 2:
        print("响应格式错误", file=sys.stderr)
        return []
    
    data_part = response_json[1]
    if not data_part or not isinstance(data_part, dict):
        print("响应数据格式错误", file=sys.stderr)
        return []
    
    result = data_part.get('Result', {})
    if not result:
        print("未找到Result字段", file=sys.stderr)
        return []
    
    data_list = result.get('List', [])
    if not isinstance(data_list, list):
        print("List字段不是列表类型", file=sys.stderr)
        return []
    
    return data_list

def format_time_field(value: Union[int, str, float], raw_timestamp: bool = False) -> Union[str, int, float]:
    """
    格式化时间字段
    
    Args:
        value: 时间值，可以是毫秒时间戳、秒时间戳或时间字符串
        raw_timestamp: 是否输出原始时间戳
    
    Returns:
        格式化后的时间字符串或原始时间戳
    """
    if value is None:
        return None
    
    # 如果是字符串，尝试判断是否为时间戳
    if isinstance(value, str):
        # 如果已经是格式化的时间字符串，直接返回
        if not value.isdigit():
            return value
        # 如果是数字字符串，转换为整数
        value = int(value)
    
    # 如果用户要求原始时间戳，直接返回
    if raw_timestamp:
        return value
    
    # 处理时间戳
    try:
        # 判断是毫秒还是秒时间戳
        if value > 1e12:  # 大于 2001-09-09 的时间戳，认为是毫秒
            dt = datetime.fromtimestamp(value / 1000.0)
            # 提取毫秒部分
            milliseconds = int((value % 1000))
        else:  # 秒时间戳
            dt = datetime.fromtimestamp(float(value))
            milliseconds = -1
        
        # 格式化为中文格式：2025年08月09日 22:08:17.345
        formatted_time = dt.strftime(f"%Y年%m月%d日 %H:%M:%S")
        if milliseconds >= 0:
            formatted_time += f".{milliseconds:03d}"
        
        return formatted_time
    except (ValueError, OSError, TypeError) as e:
        # 如果时间戳格式错误，返回原始值
        print(f"时间格式化错误: {value} -> {e}", file=sys.stderr)
        return value

def merge_output_fields(url_fields: List[str], additional_fields: List[str]) -> List[str]:
    """添加固定字段并按顺序合并URL和命令行字段，将整条记录字段放在最后"""
    merged_fields = []
    include_full_record = False
    for field in list(FIXED_OUTPUT_FIELDS) + url_fields + additional_fields:
        field = field.strip()
        if not field:
            continue
        if field == FULL_RECORD_FIELD:
            include_full_record = True
        elif field not in merged_fields:
            merged_fields.append(field)
    if include_full_record:
        merged_fields.append(FULL_RECORD_FIELD)
    return merged_fields


def get_source_fields(fields: List[str]) -> List[str]:
    """获取查询所需的一级字段并保持原有顺序"""
    source_fields = []
    for field in fields:
        if field == FULL_RECORD_FIELD:
            continue
        source_field = field.split('.', 1)[0]
        if source_field not in source_fields:
            source_fields.append(source_field)
    return source_fields

def get_field_value(row: Dict, field: str) -> Any:
    """按点分隔路径读取字段，路径中的JSON字符串会被自动解析"""
    path = field.split('.')
    if path[0] not in row:
        return None

    value = row[path[0]]
    for key in path[1:]:
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                return None
        if not isinstance(value, dict) or key not in value:
            return None
        value = value[key]
    return value

def filter_and_format_fields(data: List[Dict], fields_to_keep: List[str], raw_timestamp: bool = False) -> List[Dict]:
    """过滤数据，只保留指定字段，并格式化时间字段"""
    if not fields_to_keep or not data:
        return []
    
    filtered_data = []
    
    for row in data:
        filtered_row = {}
        for field in fields_to_keep:
            if field == FULL_RECORD_FIELD:
                continue
            value = get_field_value(row, field)
            if value is not None:
                # 如果字段名包含"time"或"timestamp"，并且不是raw_timestamp模式，则格式化时间
                if (field.lower() == 'time' or field.lower() == 'timestamp' or
                    field.lower() == 'ts') and not raw_timestamp:
                    filtered_row[field] = format_time_field(value, raw_timestamp)
                else:
                    filtered_row[field] = value
            else:
                filtered_row[field] = None
        if FULL_RECORD_FIELD in fields_to_keep:
            filtered_row[FULL_RECORD_FIELD] = json.dumps(row, ensure_ascii=False)
        filtered_data.append(filtered_row)
    
    return filtered_data

def save_to_csv(data: List[Dict], filename: str, fields: Optional[List[str]] = None) -> bool:
    """保存数据到CSV文件"""
    if not data:
        print("没有数据可保存", file=sys.stderr)
        return False
    
    if fields:
        csv_fields = fields
    else:
        csv_fields = list(data[0].keys())
    
    try:
        with open(filename, 'w', newline='', encoding='utf-8-sig') as csvfile:
            writer = csv.DictWriter(csvfile, fieldnames=csv_fields)
            writer.writeheader()
            for row in data:
                csv_row = {
                    key: json.dumps(value, ensure_ascii=False) if isinstance(value, (dict, list)) else value
                    for key, value in row.items()
                }
                writer.writerow(csv_row)
        
        print(f"数据已保存到: {filename}", file=sys.stderr)
        print(f"总记录数: {len(data)}", file=sys.stderr)
        return True
    except Exception as e:
        print(f"保存CSV文件失败: {e}", file=sys.stderr)
        return False

def get_all_pages(cookie_connect_sid: str, namespace: str, start_ms: int, 
                  end_ms: int, filters: List[Dict], limit: int = 200, 
                  max_records: int = 1000) -> List[Dict]:
    """获取所有分页数据"""
    all_data = []
    offset = 0
    page = 1
    total_pages_needed = (max_records + limit - 1) // limit  # 向上取整计算需要的总页数
    
    print(f"\n开始获取数据，每页{limit}条，最多{max_records}条...", file=sys.stderr)
    print(f"最多需要请求{total_pages_needed}次，为防止QPS过高，每两次请求之间等待1秒", file=sys.stderr)
    
    while len(all_data) < max_records:
        print(f"正在获取第{page}页，offset={offset}...", file=sys.stderr)
        
        request_data = build_jsonrpc_request(namespace, start_ms, end_ms, filters, limit, offset)
        response_json = query_logs_jsonrpc(cookie_connect_sid, request_data)
        
        if not response_json:
            print(f"第{page}页获取失败", file=sys.stderr)
            break
        
        page_data = extract_data_from_response(response_json)
        if not page_data:
            print("已无更多数据", file=sys.stderr)
            break
        
        all_data.extend(page_data)
        print(f"第{page}页获取到{len(page_data)}条数据，总计{len(all_data)}条", file=sys.stderr)
        
        if len(page_data) < limit:
            print("已获取所有数据", file=sys.stderr)
            break
        
        offset += limit
        page += 1
        
        # 避免QPS过高，每两次请求之间等待1秒（除了最后一次请求）
        if len(all_data) < max_records and len(page_data) >= limit:
            # print("等待1秒，避免QPS过高...", file=sys.stderr)
            time.sleep(1)
    
    print(f"数据获取完成，共获取{len(all_data)}条记录", file=sys.stderr)
    return all_data[:max_records]

def print_compact_json(data: List[Dict], fields: Optional[List[str]] = None, raw_timestamp: bool = False):
    """以紧凑的JSON格式输出到控制台，每行一条记录"""
    if fields:
        output_data = filter_and_format_fields(data, fields, raw_timestamp)
    else:
        if raw_timestamp:
            output_data = data
        else:
            # 没有指定字段时，也需要格式化时间字段
            output_data = []
            for row in data:
                formatted_row = {}
                for key, value in row.items():
                    if (key.lower().endswith('time') or 
                        key.lower().endswith('timestamp') or
                        key.lower() == 'ts') and not raw_timestamp:
                        formatted_row[key] = format_time_field(value, raw_timestamp)
                    else:
                        formatted_row[key] = value
                output_data.append(formatted_row)
    
    # 每行输出一条JSON记录，而不是一个JSON数组
    for record in output_data:
        # 使用紧凑格式输出每条记录
        print(json.dumps(record, separators=(',', ':'), ensure_ascii=False))

def detect_time_fields(data: List[Dict]) -> List[str]:
    """检测数据中可能的时间字段"""
    if not data:
        return []
    
    time_fields = []
    # 检查前几条记录，找出可能的时间字段
    sample_size = min(5, len(data))
    for i in range(sample_size):
        for field, value in data[i].items():
            if (field.lower().endswith('time') or 
                field.lower().endswith('timestamp') or
                field.lower() == 'ts'):
                if field not in time_fields:
                    time_fields.append(field)
    
    return time_fields

def main():
    parser = argparse.ArgumentParser(
        description='日志查询工具 - 默认输出紧凑JSON，支持时间格式化',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
时间字段格式化:
  默认情况下，字段名包含"time"、"timestamp"或"ts"的字段会被格式化为：
  2025年08月09日 22:08:17.345
  使用 --raw-timestamp 参数可输出原始毫秒时间戳

示例:
  # 基本用法：从URL查询并输出紧凑JSON（时间自动格式化）
  python log_query.py --url "URL" --sid "SID"
  
  # 输出原始时间戳
  python log_query.py --url "URL" --sid "SID" --raw-timestamp
  
  # 保存为CSV文件（时间自动格式化）
  python log_query.py --url "URL" --sid "SID" --fields "device_id,time" --output "output.csv"
  
  # 保存为CSV文件（原始时间戳）
  python log_query.py --url "URL" --sid "SID" --fields "device_id,timestamp" --output "output.csv" --raw-timestamp
  
  # 自定义时间范围和namespace
  python log_query.py --url "URL" --sid "SID" --start "2025-12-20 00:00:00" --end "2025-12-20 23:59:59" --namespace "custom_namespace"
  
  # 获取更多数据
  python log_query.py --url "URL" --sid "SID" --max-records 5000
        '''
    )
    
    # 必需参数
    parser.add_argument('--url', type=str, help='原始日志查询URL', required=True)
    parser.add_argument('--sid', type=str, help='connect.sid cookie值（查询URL时需要）', default='s%3AwkvUwO_OHKrQ-h7rWqPgxwQRzG2KOfjX.TscRKXAPHno3kPtD5p5Z4ZVZURDnAbSE0IAmANtJI84')
    
    # 可选参数
    parser.add_argument('--start', type=str, help='开始时间(格式: YYYY-MM-DD HH:MM:SS)')
    parser.add_argument('--end', type=str, help='结束时间(格式: YYYY-MM-DD HH:MM:SS)')
    parser.add_argument('--filter', type=str, help='自定义过滤条件(JSON格式)')
    parser.add_argument('--fields', type=str, help='在URL已有字段外新增的字段列表(逗号分隔，详情表示整条记录JSON)')
    parser.add_argument('--output', type=str, help='默认输出到csv文件，指定为console时输出到控制台')
    parser.add_argument('--limit', type=int, default=1000, help='每页记录数(默认: 1000)')
    parser.add_argument('--max-records', type=int, default=10000, help='最大记录数(默认: 10000)')
    parser.add_argument('--namespace', type=str, help='自定义Namespace，覆盖URL中的设置')
    parser.add_argument('--raw-timestamp', action='store_true', help='输出原始时间戳，而不是格式化时间')
    
    args = parser.parse_args()
    all_data = []
    output_file = None
    
    if args.url:
        if not args.sid:
            print("错误: 查询URL时需要提供 --sid 参数", file=sys.stderr)
            sys.exit(1)
            
        print("正在解析URL参数...", file=sys.stderr)
        original_params = parse_url_params(args.url)
        
        # 处理namespace参数：优先使用命令行参数，其次使用URL中的参数
        if args.namespace:
            namespace = args.namespace
        else:
            namespace = original_params.get('Namespace', '')
            if not namespace:
                namespace = "live_push_20250804_doris"  # 默认值
        
        # 处理时间参数
        if args.start:
            start_ms = int(datetime.strptime(args.start, '%Y-%m-%d %H:%M:%S').timestamp() * 1000)
        else:
            start_ms = original_params.get('Start', 0)
        
        if args.end:
            end_ms = int(datetime.strptime(args.end, '%Y-%m-%d %H:%M:%S').timestamp() * 1000)
        else:
            end_ms = original_params.get('End', 0)
        
        # 处理过滤器参数
        if args.filter:
            try:
                filters = json.loads(args.filter)
            except json.JSONDecodeError as e:
                print(f"错误: 过滤器必须是有效的JSON格式: {e}", file=sys.stderr)
                sys.exit(1)
        else:
            filters = original_params.get('Filter', [])

        # 处理字段参数，如果参数没有指定，就跟url中解析的一致
        url_fields = original_params.get('fieldList', [])
        has_explicit_fields = bool(args.fields or url_fields)
        additional_fields = args.fields.split(',') if args.fields else []
        fields_to_output = merge_output_fields(url_fields, additional_fields)
        fields_to_fetch = get_source_fields(fields_to_output)

        # 生成输出文件名，如果用户指定了输出文件名，使用用户指定的
        if args.output != 'console':
            if args.output and args.output.lower().endswith('.csv'):
                output_file = args.output
            else:
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                output_file = f"trace_query_result_{timestamp}.csv"
        
        print(f"\n查询参数:", file=sys.stderr)
        print(f"Namespace: {namespace}", file=sys.stderr)
        print(f"时间范围: {datetime.fromtimestamp(start_ms/1000)} 到 {datetime.fromtimestamp(end_ms/1000)}", file=sys.stderr)
        if filters:
            print(f"过滤器: {json.dumps(filters, indent=2, ensure_ascii=False)}", file=sys.stderr)
        if fields_to_fetch:
            print(f"查询字段: ", str(fields_to_fetch))
        if fields_to_output != fields_to_fetch:
            print(f"输出字段: ", str(fields_to_output))
        if output_file:
            print(f"输出文件: ", output_file)
        else:
            print(f"输出到控制台")
        
        # 获取所有数据
        all_data = get_all_pages(
            args.sid, namespace, start_ms, end_ms, 
            filters, args.limit, args.max_records
        )
        
    if not all_data:
        print("未获取到任何数据", file=sys.stderr)
        sys.exit(0)
    
    # 检测时间字段
    time_fields = detect_time_fields(all_data)
    if time_fields and not args.raw_timestamp:
        print(f"检测到时间字段: {', '.join(time_fields)}，将自动格式化为中文时间格式", file=sys.stderr)
        print(f"使用 --raw-timestamp 参数可输出原始时间戳", file=sys.stderr)

    # 输出处理
    if output_file and output_file != "":
        # 保存为CSV文件
        filtered_data = filter_and_format_fields(all_data, fields_to_output, args.raw_timestamp)
        
        if not filtered_data:
            print("过滤后无数据", file=sys.stderr)
            sys.exit(0)
        
        # 保存为CSV文件
        save_to_csv(filtered_data, output_file, fields_to_output)
        
        # 同时保存原始JSON数据（包含原始时间戳）
        # if not args.raw_timestamp:
        #     json_output = f"{os.path.splitext(output_file)[0]}_raw.json"
        #     with open(json_output, 'w', encoding='utf-8') as f:
        #         json.dump(all_data, f, indent=2, ensure_ascii=False)
        #     print(f"原始JSON数据（包含原始时间戳）已保存到: {json_output}", file=sys.stderr)
        
    else:
        # 默认输出JSON到控制台
        print_compact_json(all_data, fields_to_output if has_explicit_fields else None, args.raw_timestamp)

if __name__ == "__main__":
    main()
