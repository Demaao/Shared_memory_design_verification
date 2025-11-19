import re                             # To extract numbers from text
import matplotlib.pyplot as plt # type: ignore
import os

# Shared Memory Verification Tool

def parse_simulation_log(file_path):
    with open(file_path, "r") as f:
        text = f.read()

    # Find TEST_TYPE (e.g., HASHED_READS)
    test_type_match = re.search(r"TEST_TYPE:\s*([A-Z_]+)", text)
    test_type = test_type_match.group(1) if test_type_match else "UNKNOWN"

    # Search for numeric values
    total_drops = re.search(r"Total dropp:\s*(\d+)", text)
    avg_latency = re.search(r"Global Average Latency\s*=\s*([\d.]+)", text)
    max_latency = re.search(r"Global Max Latency\s*=\s*(\d+)", text)
    switch_collisions = re.search(r"Total switch collisions:\s*(\d+)", text)
    memory_collisions = re.search(r"Total memory collisions:\s*(\d+)", text)

    # Convert matches into numbers
    drops = int(total_drops.group(1)) if total_drops else 0
    avg_lat = float(avg_latency.group(1)) if avg_latency else 0.0
    max_lat = int(max_latency.group(1)) if max_latency else 0
    sw_col = int(switch_collisions.group(1)) if switch_collisions else 0
    mem_col = int(memory_collisions.group(1)) if memory_collisions else 0

    return {
        "test_type": test_type,
        "drops": drops,
        "avg_latency": avg_lat,
        "max_latency": max_lat,
        "switch_collisions": sw_col,
        "memory_collisions": mem_col
    }

def analyze_results(data):
    print(f"Simulation Verification Report ({data['test_type']}) ")
    print(f"Total Switch Collisions : {data['switch_collisions']}")
    print(f"Total Memory Collisions : {data['memory_collisions']}")
    print(f"Total Drops             : {data['drops']}")
    print(f"Average Latency (cycles): {data['avg_latency']}")
    print(f"Max Latency (cycles)    : {data['max_latency']}")

    # Efficiency calculations
    efficiency = 0
    if data["switch_collisions"] > 0:
        efficiency = (1 - data["drops"] / data["switch_collisions"]) * 100

    print(f"Network Efficiency       : {efficiency:.2f}%")

    # Consistency checks
    if data["drops"] > data["switch_collisions"]:
        print("Warning: More drops than collisions — check simulation!")
    elif data["memory_collisions"] > 0:
        print("Memory conflicts detected — possible bottleneck.")
    else:
        print("Simulation results are consistent and stable.")

    return efficiency

def plot_results(data, efficiency):
    categories = ["Switch Collisions", "Drops", "Memory Collisions"]
    values = [data["switch_collisions"], data["drops"], data["memory_collisions"]]

    # Create bar chart
    plt.figure(figsize=(7, 5))
    bars = plt.bar(categories, values, color=["skyblue", "salmon", "gray"])

    #  Titles and labels
    plt.title(f"{data['test_type']} — Efficiency = {efficiency:.2f}%")
    plt.ylabel("Count")
    plt.xlabel("Metric Type")

    # Show values above each bar
    for bar in bars:
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2, yval + 2, f"{int(yval)}", 
                 ha="center", va="bottom", fontsize=9)

    # Save the graph with test name
    file_name = f"results_{data['test_type']}.png"
    plt.tight_layout()
    plt.savefig(file_name, dpi=300)
    print(f"Graph saved as: {file_name}")
    plt.show()


# Run the analysis
if __name__ == "__main__":
    log_path = "../simulation/simulation_K5_MIXED_RW.txt"
    results = parse_simulation_log(log_path)
    efficiency = analyze_results(results)
    plot_results(results, efficiency)
