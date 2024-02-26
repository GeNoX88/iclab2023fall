# ========================================================
# Project:  Lab01 reference code
# File:     Test_data_gen_ref.py
# Author:   Lai Lin-Hung @ Si2 Lab
# Date:     2021.09.15
# ========================================================

# ++++++++++++++++++++ Import Package +++++++++++++++++++++

# ++++++++++++++++++++ Function +++++++++++++++++++++
import random
def calculate(w, vgs, vds, mode):
    Id = []
    Gm = []
    n = []
    for i in range(6):
        von = vgs[i]-1
        if(von > vds[i]):
            Id.append((w[i] * vds[i]*(2*von - vds[i]))//3)
            Gm.append((w[i] * vds[i] * 2)//3)
        else :
            Id.append((w[i] * von * von)//3)
            Gm.append((w[i] * von * 2)//3)
        
    for i in range (6):
        if(mode == 1 or mode == 3): #mode[0] == 1
            n.append(Id[i])
        else :     
            n.append(Gm[i])
    Id.clear()
    Gm.clear()

    n.sort(reverse = True)    #n[0] is the biggest

    if(mode == 0):
        out = (n[3] + n[4] + n[5])//3
    elif(mode == 1):
        out = (3 * n[3] + 4 * n[4] + 5 * n[5])//12
    elif(mode == 2):
        out = (n[0] + n[1] + n[2])//3
    else :          
        out = (3 * n[0] + 4 * n[1] + 5 * n[2])//12
    return out

def gen_test_data(input_file_path,output_file_path):
    # initial File path
    pIFile = open(input_file_path, 'w')
    pOFile = open(output_file_path, 'w')
    
    # Set Pattern number 
    PATTERN_NUM = 30000
    pIFile.write(str(PATTERN_NUM)+"\n")
    for j in range(PATTERN_NUM):
        mode=0
        out_n=0
        # Todo: 
        # You can generate test data here
        mode = random.randint(0,3)
        w = []
        vgs = []
        vds = []
        for i in range(6):
            w.append(random.randint(1, 7))
            vgs.append(random.randint(1, 7))
            vds.append(random.randint(1, 7))
        out_n = calculate (w, vgs, vds, mode)

        # Output file
        pIFile.write(f"{mode}\n")
        for i in range(6):
            pIFile.write(f"{w[i]} {vgs[i]} {vds[i]}\n")
        pOFile.write(f"{out_n}\n")
    pIFile.close()
    pOFile.close()
# ++++++++++++++++++++ main +++++++++++++++++++++
def main():
    gen_test_data("./input.txt","./output.txt")

if __name__ == '__main__':
    main()