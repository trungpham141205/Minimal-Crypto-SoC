# Kiến trúc SoC hiện tại

[Mở sơ đồ kiến trúc HTML](soc-current-architecture.html).

Đối chiếu mã nguồn ngày 2026-09-06. Phạm vi là hierarchy được khai báo từ `soc_top.sv`; đây là khảo sát RTL, chưa phải xác nhận build hoặc mô phỏng thành công.

## Cấu trúc tích hợp

- `soc_top/u_cpu`: `risc_top`, CPU RV32I single-cycle với cơ chế stall khi truy cập dữ liệu. Bên trong gồm PC, bộ nhớ lệnh, control unit, register file, immediate generator, ALU, branch và write-back mux.
- `u_cpu/dut_instruction_memory`: `instruction_memory`, mảng 1024 × 32 bit (4 KiB), đọc tổ hợp bằng `pc[11:2]`, nạp `program.hex`. Đường fetch riêng bên trong CPU, không đi qua AXI dữ liệu.
- `soc_top/u_axi_master`: `axi_master_wrapper`, chuyển load/store native thành AXI. Mỗi lần chỉ có một giao dịch đang chờ, một beat 32 bit; xử lý chọn byte/halfword và sign/zero extension cho load, WSTRB cho store. `stall_o` giữ PC và ngăn ghi register file trong lúc đợi.
- `soc_top/u_interconnect`: `axi_interconnect_1m3s`, giải mã địa chỉ và định tuyến một master tới ba slave. Các liên kết dùng `axi_full_if`, địa chỉ và dữ liệu 32 bit, ID 4 bit, các kênh AW/W/B/AR/R. Địa chỉ ngoài map trả DECERR; master hiện không chuyển response lỗi thành trap CPU.
- `soc_top/u_sram_slave`: `axi_sram_slave`, điều khiển SRAM single-port đồng bộ. Ghi đủ word trực tiếp; ghi một phần dùng read-modify-write vì macro không có byte write enable.
- `soc_top/u_uart_slave`: `uart_axi_slave`, thanh ghi MMIO và `uart_core`. Core chứa baud generator, bộ đồng bộ RX, TX và RX. Chân ngoài là `uart_rx_i` và `uart_tx_o`.
- `soc_top/u_aes_slave`: `aes_axi_slave`, các thanh ghi plaintext/key/ciphertext và điều khiển `aes_cipher_top`. AES-256 có block 128 bit, key 256 bit, initial AddRoundKey + 13 round thường + round cuối, với các thanh ghi pipeline state/valid. Wrapper chỉ nhận một phép mã hóa tại một thời điểm; CPU kiểm tra busy/done qua MMIO.

Toàn bộ các khối tích hợp dùng `clk` và reset active-low `rstn`. Hai chân debug là `cpu_stall_debug` và `aes_done_debug` (done sticky của wrapper). Không có đường interrupt nối về CPU trong `soc_top`.

## Address map

| Không gian | Địa chỉ / offset | Dung lượng / nội dung |
|---|---|---|
| Instruction fetch riêng | PC index `[11:2]` | 1024 word × 32 bit = 4 KiB; không phải AXI slave |
| Data SRAM | `0x0000_0000–0x0000_01FF` | Cửa sổ decode 512 byte; macro dự kiến 256 × 32 bit = 1 KiB |
| UART MMIO | `0x1000_0000–0x1000_0FFF` | Cửa sổ địa chỉ 4 KiB |
| AES MMIO | `0x2000_0000–0x2000_0FFF` | Cửa sổ địa chỉ 4 KiB |

4 KiB ở các ngoại vi là kích thước cửa sổ giải mã, không phải dung lượng thanh ghi được triển khai.

| Ngoại vi | Offset | Thanh ghi |
|---|---|---|
| UART | `0x00 / 0x04 / 0x08` | TXDATA / RXDATA / STATUS |
| UART | `0x0C / 0x10` | CONTROL / BAUDRATE |
| AES | `0x00 / 0x04` | CONTROL (start bit 0, clear done bit 1) / STATUS (busy bit 0, done bit 1) |
| AES | `0x10–0x1C` | PT0–PT3, 4 word; PT0 tương ứng bits `[127:96]` |
| AES | `0x20–0x3C` | KEY0–KEY7, 8 word; KEY0 tương ứng bits `[255:224]` |
| AES | `0x40–0x4C` | CT0–CT3, 4 word |

## Cách dữ liệu di chuyển

CPU điều khiển SRAM, UART và AES qua load/store MMIO. Khi xử lý dữ liệu nhận qua UART, CPU đọc RXDATA, ghi plaintext/key vào AES, ghi START, poll STATUS rồi đọc ciphertext và ghi TXDATA. Có thể dùng SRAM làm vùng lưu trung gian. Không có đường truyền trực tiếp UART–AES hoặc AES–SRAM và không có DMA trong top hiện tại.

Firmware đang có tại `firmware/program.S` là smoke test SRAM, AES known-answer test và gửi ký tự P/F qua UART. Các testbench khác mô tả luồng staging SRAM và UART runtime; không suy ra các test đã pass từ chuỗi `$display` trong mã nguồn.

## Điểm chưa đồng bộ trong snapshot

1. `axi_sram_slave.sv` instantiate `sram_256x32_wrapper`, và `filelist_soc.f` cũng tham chiếu file tên này, nhưng snapshot hiện chỉ có module/file `shared_sram_256x32_wrapper` và `instruction_sram_256x32_wrapper`. Kết nối tới SRAM macro là ý định thể hiện qua cổng wrapper; hierarchy hiện còn thiếu module đúng tên để elaborate.
2. `filelist_soc.f` ghi `tb_soc_uart_runtime.sv` ở thư mục gốc, trong khi file hiện ở `TB/tb_soc_uart_runtime.sv`.
3. Instruction SRAM wrapper có trong thư mục nhưng chưa được instantiate bởi `risc_top`; bộ nhớ lệnh đang dùng mảng behavioral `instruction_memory`.
4. CNN, DMA, AES-GCM, Key Vault, Secure Boot và PQC xuất hiện trong tài liệu lộ trình nhưng chưa được tích hợp trong `soc_top.sv`. Các thanh ghi key AES hiện đọc được qua MMIO.

## Nguồn đối chiếu

- `soc_top.sv`
- `RV32I_Single_Cycle/risc_top.sv`
- `RV32I_Single_Cycle/instruction_memory.sv`
- `RV32I_Single_Cycle/shared_sram_256x32_wrapper.sv`
- `AXI/axi_master_wrapper.sv`
- `AXI/axi_interconnect_1m3s.sv`
- `AXI/axi_sram_slave.sv`
- `AXI/uart_axi_slave.sv`
- `AXI/aes_axi_slave.sv`
- `AES/rtl/aes_cipher_top.sv`
- `UART/uart_core.sv`
- `filelist_soc.f`
