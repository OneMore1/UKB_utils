import numpy as np
import os
import argparse

def process_fmri_csv_to_npy(source_dir, output_dir):
    """
    读取 UKB fMRI CSV.gz (假设原始格式为 ROI x Time)，
    去除表头(Row 0)和索引(Col 0)，对时间维度做 Z-score，
    拼接 Schaefer100+Tian50，保存为 .npy。
    """
    
    # 1. 确保输出目录存在
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        print(f"创建输出目录: {output_dir}")

    files = {
        'tian': 'fMRI.Tian_Subcortex_S3_3T.csv.gz',
        'sch100': 'fMRI.Schaefer17n100p.csv.gz',
        'sch400': 'fMRI.Schaefer17n400p.csv.gz',
        'glasser': 'fMRI.Glasser.csv.gz'
    }

    # Z-score 函数
    def zscore_data(data, axis=1):
        """
        axis=1: 对每一行(每个ROI)的所有时间点做标准化
        """
        mean = np.mean(data, axis=axis, keepdims=True)
        std = np.std(data, axis=axis, keepdims=True)
        # 加上 1e-8 防止除以 0 (例如该 ROI 信号全为 0)
        return (data - mean) / (std + 1e-8)

    # 辅助函数
    def load_clean_csv(filename):
        path = os.path.join(source_dir, filename)
        if not os.path.exists(path):
            print(f"警告: 文件不存在 {path}")
            return None
        
        try:
            # 假设原始文件是 ROI x Time (带表头和索引列)
            raw_data = np.genfromtxt(path, delimiter=',')
            
            # 去掉第一行(Header)和第一列(Index)
            # 结果形状应为 (N_ROI, N_Time)
            clean_data = raw_data[1:, 1:]
            
            # 立即进行 Z-score 标准化
            # 我们希望每个 ROI 自身在时间上变为均值0方差1
            # 输入 (ROI, Time), 在 axis=1 上操作
            norm_data = zscore_data(clean_data, axis=1)
            
            return norm_data
        except Exception as e:
            print(f"读取错误 {filename}: {e}")
            return None

    # ================= 2. 读取数据 =================
    data_tian = load_clean_csv(files['tian'])      # 预期 (50, 490)
    data_sch100 = load_clean_csv(files['sch100'])  # 预期 (100, 490)
    data_sch400 = load_clean_csv(files['sch400'])  # 预期 (400, 490)
    data_glasser = load_clean_csv(files['glasser']) # 预期 (360, 490)

    # ================= 3. 处理与保存 =================
    
    # --- 任务 A: 分别保存 Schaefer100 (100 ROI) 和 Tian (50 ROI) ---
    if data_sch100 is not None and data_tian is not None:
        save_path_100 = os.path.join(output_dir, 'roi100.npy')
        np.save(save_path_100, data_sch100)
        print(f"已保存: {save_path_100}, 形状: {data_sch100.shape}")

        save_path_50 = os.path.join(output_dir, 'roi50.npy')
        np.save(save_path_50, data_tian)
        print(f"已保存: {save_path_50}, 形状: {data_tian.shape}")


    # --- 任务 B: 保存 Schaefer400 ---
    if data_sch400 is not None:
        save_path = os.path.join(output_dir, 'roi400.npy')
        np.save(save_path, data_sch400)
        print(f"已保存: {save_path}, 形状: {data_sch400.shape}")

    # --- 任务 C: 保存 Glasser ---
    if data_glasser is not None:
        save_path = os.path.join(output_dir, 'roi360.npy')
        np.save(save_path, data_glasser)
        print(f"已保存: {save_path}, 形状: {data_glasser.shape}")
        
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="处理 UKB fMRI CSV.gz 文件并保存为 .npy 格式")
    parser.add_argument('--source_dir', type=str, required=True, help='源数据目录，包含 fMRI CSV.gz 文件')
    parser.add_argument('--output_dir', type=str, required=True, help='输出目录，用于保存处理后的 .npy 文件')
    
    args = parser.parse_args()
    
    process_fmri_csv_to_npy(args.source_dir, args.output_dir)
