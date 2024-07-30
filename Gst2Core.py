#!/usr/bin/env python3

import sys, re

replacements = {
    r'GstFlowReturn': r'CoreFlowStatus',
    r'GstStateChangeReturn': r'CoreStatusReturn',
    r'GstStateChange': r'CoreStatusChange',
    r'gst_event_get_seqnum': r'CORE_EVENT_SEQNUM',
    r'gst_event_set_seqnum\( *(.*?), *(.*?)\);': r'CORE_EVENT_SEQNUM(\g<1>) = \g<2>;',
    ######################## GST LOG ####################################### 
    r'\bGST_(DEBUG|INFO|WARNING|ERROR)_OBJECT *\(': r'CORE_\g<1>_OBJECT(', # ① GST_DEBUG_OBJECT -> CORE_DEBUG_OBJECT
    r'\bGST_([DIWE])(EBUG|NFO|ARNING|RROR) *\(': r'CORE_LOG\g<1>(', # ② GST_DEBUG -> CORE_LOGD
    r'\bGST_CAT_(DEBUG|INFO|WARNING|ERROR)_OBJECT *\(.+?, *': r'CORE_\g<1>_OBJECT(', # ③ GST_CAT_DEBUG_OBJECT(cat, -> CORE_DEBUG_OBJECT(
    r'\bGST_CAT_([DIWE])(EBUG|NFO|ARNING|RROR) *\(.+?, *': r'CORE_LOG\g<1>(', # ④ GST_CAT_DEBUG(cat, -> CORE_LOGD(
    r'\bGST_(FIXME_OBJECT *\(|CAT_FIXME_OBJECT *\(.+?, *)': r'CORE_WARNING_OBJECT(', # 同 ① 和 ③
    r'\bGST_(LOG_OBJECT *\(|CAT_LOG_OBJECT *\(.+?, *)': r'CORE_DEBUG_OBJECT(', # 同 ① 和 ③
    r'\bGST_(TRACE_OBJECT *\(|CAT_TRACE_OBJECT *\(.+?, *)': r'CORE_VERBOSE_OBJECT(', # 同 ① 和 ③
    r'\bGST_(FIXME *\(|CAT_FIXME *\(.+?, *)': r'CORE_LOGW(', # 同 ② 和 ④
    r'\bGST_(LOG *\(|CAT_LOG *\(.+?, *)': r'CORE_LOGD(', # 同 ② 和 ④
    r'\bGST_(TRACE *\(|CAT_TRACE *\(.+?, *)': r'CORE_LOGV(', # 同 ② 和 ④
    ######################## GST LOG END ####################################### 
    r'\bGST_STATE_CHANGE_(PAUSE|[A-Z]+?)D?_TO_(PAUSE|[A-Z]+?)D?': r'CORE_STATUS_CHANGE_\g<1>_TO_\g<2>',
    r'Gst': r'Core',
    r'gst': r'core',
    r'GST': r'CORE',
    r'\bTRUE\b': r'true',
    r'\bFALSE\b': r'false',
    r'\bGCond\b': r'CoreCondition',
    r'\bG(Type|Quark|List|Array|Queue|Mutex|Object|ObjectClass|Value|ParamSpec)\b': r'Core\g<1>',
    r'\bG_PARAM_(READABLE|WRITABLE|READWRITE|CONSTRUCT|CONSTRUCT_ONLY)\b': r'CORE_PARAM_FLAG_\g<1>',
    r'\bG_PARAM_STATIC_STRINGS\b': r'CORE_PARAM_STATIC_STRING',
    r'\bG_OBJECT_WARN_INVALID_PROPERTY_ID\b': 'CORE_WARNING_OBJ_INVALID_PROPTERTY_ID',
    r'\bG_(OBJECT_\w+|TYPE_\w+|PARAM_\w+|(UN)?LIKELY)\b': r'CORE_\g<1>',
    r'g_debug': r'CORE_LOGD',
    r'g_info|g_message': r'CORE_LOGI',
    r'g_warning|g_critical': r'CORE_LOGW',
    r'g_error': r'CORE_LOGE',
    r'g_fatal': r'CORE_LOGF',
    r'\bg_object_class_install_property\b': r'core_object_class_register_property',
    r'\bg_return_val_if_fail\b': r'core_if_return_var_fail',
    r'\bg_return_if_fail\b': r'core_if_return_fail',
    r'\bg_assert\b': r'CORE_DCHECK',
    r'\bg_snprintf\b': r'snprintf',
    r'\bg_(mutex|cond|rw_lock)_clear\b': r'core_\g<1>_clean',
    ######################## g/gst_value_set/get ####################################### 
    r'\bg_(value_[sg]et_)(char|schar)\b': r'core_\g<1>i8',
    r'\bg_(value_[sg]et_)uchar\b': r'core_\g<1>u8',
    r'\bg_(value_[sg]et_(boolean|enum))\b': r'core_\g<1>',
    r'\bg_(value_[sg]et_)int\b': r'core_\g<1>i32',
    r'\bg_(value_[sg]et_)(uint|gtype)\b': r'core_\g<1>u32',
    r'\bg_(value_[sg]et_)(long|int64)\b': r'core_\g<1>i64',
    r'\bg_(value_[sg]et_)(ulong|uint64)\b': r'core_\g<1>u64',
    r'\bg_(value_[sg]et_)float\b': r'core_\g<1>f32',
    r'\bg_(value_[sg]et_)double\b': r'core_\g<1>f64',
    r'\bg_(value_[sg]et_)(string|static_string)\b': r'core_\g<1>str',
    r'\bg_(value_[sg]et_)interned_string\b': r'core_\g<1>intern_str',
    r'\bg_(value_[sg]et_)pointer\b': r'core_\g<1>ptr',
    r'\bg_(value_[sg]et_)pointer\b': r'core_\g<1>ptr',
    r'\bgst_(value_[sg]et_)int_range\b': r'core_\g<1>range_i32',
    r'\bgst_(value_[sg]et_)(int64|double)_range\b': r'core_\g<1>range_f64',
    r'\bgst_(value_[sg]et_)(fraction|flagset)\b': r'core_\g<1>fraction_i32',
    r'\bgst_(value_[sg]et_)bitmask\b': r'core_\g<1>u64',
    r'\bgst_(value_[sg]et_)(caps|structure|caps_features)\b': r'core_\g<1>ptr',
    ######################## g/gst_value_set/get end ####################################### 
    r'\bg_(signal_\w+|queue_\w+|cond_\w+|mutex_\w+|signal_\w+|value_\w+|param_\w+|type_\w+|once_\w+|thread_\w+|atomic_\w+)\b': r'core_\g<1>',
    r'\bG_(MIN|MAX)(\w*(INT|FLOAT)\w*)\b': r'\g<2>_\g<1>',
    r'\bG_STMT_START\b': r'do',
    r'\bG_STMT_END\b': r'while',
    r'\bG_BEGIN_DECLS\b': r'CORE_DECLARE_BEGIN',
    r'\bG_END_DECLS\b': r'CORE_DECLARE_END',
    r'\bgpointer\b': r'CorePointer',
    r'\bgconstpointer\b': r'CoreConstPointer',
    r'\bguint\b': r'uint32_t',
    r'\bgsize\b': r'size_t',
    r'\bgssize\b': r'int',
    r'\bg(int|boolean|char|double)\b': r'\g<1>',
    r'\bg(u?)int(\d+)\b': r'\g<1>int\g<2>_t',
    r'\bG(Func|DestroyNotify|CompareFunc|Base\w*Func|Class\w*Func|Instance\w*Func)\b': r'Core\g<1>',
    r'\b(MIN|MAX)\b': r'CORE_\g<1>',
    #下面3句把函数声明和函数调用中的函数名与左括号(之间的空格去掉。
    r'(#define.*? +)\(': r'\g<1>@@@@@@', #防止误伤#define语句，先用特殊字符串替换规避
    r'(\w+\)?)(?<!if)(?<!for)(?<!while)(?<!switch)(?<!return) +\((?!\*\w+\) *\()': r'\g<1>(', #排除if/for/while/switch/return/函数指针等
    r'(#define.*)@@@@@@': r'\g<1>(', #还原上上句修改的#define语句
    r'(\w+) *(\*+) *(\w+)': r'\g<1> \g<2>\g<3>', #把指针表达式"Type * ptr"改为"Type *ptr"
    r'[ \t]*\n[ \t]*\{': r' {' #把单独成行的左大括号改为跟在上一行的末尾
}

if __name__ == "__main__":
    file_path = sys.argv[1]
    try:
        with open(file_path, 'r+') as file:
            file_content = file.read()
            # print('content: ', file_content)
            for pattern, replacement in replacements.items():
                # print(pattern, ":" , replacement)
                file_content = re.sub(pattern, replacement, file_content)
                # print('after: ', file_content)
            file.seek(0)
            file.truncate()
            file.write(file_content)
            print("替换完成！")
            file.close()
    except FileNotFoundError:
        print("文件未找到！")
    except Exception as e:
        print("发生错误：", e)
        if file:
            file.close()
