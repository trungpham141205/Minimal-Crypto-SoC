# BÁO CÁO THIẾT KẾ KIẾN TRÚC PHẦN CỨNG AES-256 KHÔNG PIPELINE

## 1. Giới thiệu

Advanced Encryption Standard (AES) là thuật toán mã hóa khối đối xứng được
NIST chuẩn hóa trong FIPS 197. AES làm việc trên khối dữ liệu cố định 128 bit và
hỗ trợ ba độ dài khóa: 128, 192 và 256 bit. Hậu tố trong tên AES-128, AES-192
hay AES-256 biểu thị độ dài khóa, không phải kích thước khối dữ liệu. Cả ba biến
thể đều mã hóa một khối plaintext 128 bit thành một khối ciphertext 128 bit.

Thiết kế trong đề tài là một lõi **AES-256 encryption-only**, thực hiện mã hóa
một khối 128 bit bằng khóa 256 bit. Kiến trúc datapath thuộc loại **iterative,
không pipeline**: kết quả của mỗi round được lưu vào một thanh ghi state rồi hồi
tiếp về cùng phần cứng round ở chu kỳ kế tiếp. Cách tổ chức này chỉ cho phép một
khối dữ liệu tồn tại trong lõi tại một thời điểm, đổi lại số lượng phần cứng xử
lý round nhỏ hơn nhiều so với kiến trúc unroll toàn bộ 14 round.

Các mục tiêu chính của thiết kế gồm:

- Tuân thủ luồng mã hóa AES-256 với `Nb = 4`, `Nk = 8`, `Nr = 14`.
- Giao tiếp dữ liệu theo cách viết vector chuẩn của NIST.
- Thực hiện một round trong mỗi chu kỳ clock, không chồng lấp nhiều block.
- Tạo đủ 15 round-key, từ round-key 0 đến round-key 14.
- Cung cấp tín hiệu bắt tay `start`, `busy` và `done` để tích hợp với hệ thống.
- Kiểm chứng bằng các known-answer test của FIPS 197 và NIST SP 800-38A.

Phạm vi hiện tại chỉ bao gồm phép **mã hóa một block AES**. Thiết kế chưa bao
gồm giải mã, mode of operation như GCM/CTR/CBC, bộ tạo IV/nonce, padding, xác
thực dữ liệu, cơ chế xóa khóa hay biện pháp chống side-channel. Vì vậy đây là
một cryptographic primitive, chưa phải một hệ thống bảo mật hoàn chỉnh.

## 2. Thông số tổng quát

| Thông số | Giá trị |
|---|---:|
| Kích thước plaintext | 128 bit = 16 byte |
| Kích thước ciphertext | 128 bit = 16 byte |
| Kích thước khóa chính | 256 bit = 32 byte |
| Số cột của state, `Nb` | 4 word |
| Số word của khóa, `Nk` | 8 word |
| Số round, `Nr` | 14 |
| Số round-key | 15 khóa × 128 bit |
| Tổng độ rộng bus round-key | 1920 bit |
| Số word cần dùng trong key schedule | 60 word, `w[0]` đến `w[59]` |
| Độ rộng mỗi word | 32 bit |
| Kiến trúc datapath | Iterative, không pipeline |
| Số block xử lý đồng thời | 1 |
| Độ trễ được testbench ghi nhận | 14 chu kỳ sau khi nhận `start` |
| Khoảng cách nhận hai block liên tiếp | Tối thiểu 15 chu kỳ clock |

Ở tần số clock `f_clk`, thông lượng cực đại theo giao tiếp hiện tại là:

\[
T_{block}=\frac{f_{clk}}{15}\quad\text{block/s}
\]

\[
T_{data}=\frac{128f_{clk}}{15}\quad\text{bit/s}
\]

Ví dụ, nếu đạt 100 MHz thì thông lượng lý thuyết xấp xỉ 6,67 triệu block/s,
tương đương 853,3 Mbit/s. Đây là giá trị suy ra từ số chu kỳ, chưa bao gồm thời
gian truyền dữ liệu của hệ thống bên ngoài và chưa khẳng định thiết kế đạt được
100 MHz trên một FPGA cụ thể.

## 3. Kiến trúc tổng thể

Luồng dữ liệu chính của thiết kế có thể biểu diễn như sau:

```text
                      +--------------------------+
key[255:0] ---------->| Thanh ghi khóa key_reg   |
                      +-------------+------------+
                                    |
                                    v
                      +--------------------------+
                      | Key schedule AES-256     |
                      | 15 round-key × 128 bit   |
                      +-------------+------------+
                                    |
                            chọn theo round_count
                                    |
                                    v
plaintext --> đảo byte --> AddRoundKey ban đầu --> state_reg
                                                   |
                                                   v
                         +-------------------------+------------------+
                         |                                            |
                  round 1 đến 13                                round 14
          SubBytes -> ShiftRows -> MixColumns             SubBytes -> ShiftRows
                         -> AddRoundKey                          -> AddRoundKey
                         |                                            |
                         +-------------------+------------------------+
                                             |
                                             v
                                          state_reg
                                             |
                                    đảo byte ở round cuối
                                             |
                                             v
                                      ciphertext[127:0]
```

Khối điều khiển sử dụng `round_count` 4 bit để xác định round hiện tại. Khi
`start = 1` và `busy = 0`, lõi chốt khóa, thực hiện AddRoundKey ban đầu, đặt
`round_count = 1` và đưa `busy` lên 1. Từ round 1 đến round 13, state đi qua
`aes_round`. Tại round 14, state đi qua `aes_roundlast`, ciphertext được cập
nhật, `busy` hạ xuống 0 và `done` phát xung một chu kỳ.

Thiết kế không có pipeline register giữa SubBytes, ShiftRows, MixColumns và
AddRoundKey. Do đó toàn bộ logic của một normal round nằm trên một đường tổ hợp
giữa hai lần chốt `state_reg`.

## 4. Biểu diễn state và thứ tự byte

AES xem 16 byte đầu vào như ma trận state 4 hàng × 4 cột. Nếu chuỗi đầu vào là
`a0, a1, ..., a15`, cách điền state theo cột là:

\[
S=\begin{bmatrix}
a_0 & a_4 & a_8 & a_{12}\\
a_1 & a_5 & a_9 & a_{13}\\
a_2 & a_6 & a_{10} & a_{14}\\
a_3 & a_7 & a_{11} & a_{15}
\end{bmatrix}
\]

Các module round hiện có đánh số byte nội bộ từ phần thấp của vector, tức byte
0 nằm tại `state[7:0]`. Trong khi đó, vector NIST thường được viết theo dạng hex
chuẩn với byte đầu tiên nằm bên trái, ví dụ plaintext:

```text
00112233445566778899aabbccddeeff
```

Để cổng top-level sử dụng trực tiếp cách viết này mà không làm người dùng phải
tự đảo dữ liệu, hàm `reverse_bytes` trong `aes256_core` đảo thứ tự 16 byte tại
ba vị trí:

1. Đảo plaintext trước AddRoundKey ban đầu.
2. Đảo round-key 128 bit được chọn trước khi đưa vào datapath nội bộ.
3. Đảo state của round cuối trước khi đưa ra ciphertext.

Phép đảo byte chỉ là hoán vị dây nối, không cần phép toán số học và về nguyên
tắc không tiêu thụ flip-flop.

## 5. Cốt lõi thuật toán mã hóa AES-256

Thuật toán mã hóa có thể viết ngắn gọn như sau:

```text
state = plaintext XOR round_key[0]

for round = 1 to 13:
    state = SubBytes(state)
    state = ShiftRows(state)
    state = MixColumns(state)
    state = state XOR round_key[round]

state = SubBytes(state)
state = ShiftRows(state)
state = state XOR round_key[14]

ciphertext = state
```

AddRoundKey ban đầu đưa ảnh hưởng của khóa vào state trước khi bắt đầu các
phép biến đổi round. Mười ba normal round thực hiện đầy đủ bốn bước. Final round
bỏ MixColumns theo đúng FIPS 197. Việc bỏ MixColumns ở round cuối không làm mất
khả năng khuếch tán cần thiết vì state đã trải qua 13 lần MixColumns ở các round
trước, đồng thời cấu trúc này là một phần định nghĩa chuẩn của AES.

## 6. Phân tích chi tiết từng khối RTL

### 6.1. Khối `aes_sbox`

| Thuộc tính | Giá trị |
|---|---:|
| Đầu vào | 8 bit `byte_in` |
| Đầu ra | 8 bit `byte_out` |
| Loại logic | Tổ hợp |
| Số giá trị ánh xạ | 256 |

S-box là thành phần phi tuyến cốt lõi của AES. Về mặt toán học, S-box được tạo
bằng cách lấy nghịch đảo nhân của byte trong trường hữu hạn `GF(2^8)`, với byte
0 được xử lý riêng, sau đó áp dụng một phép biến đổi affine. Trường hữu hạn AES
sử dụng đa thức bất khả quy:

\[
m(x)=x^8+x^4+x^3+x+1
\]

tương ứng hằng số `0x11B`. Hai bước nghịch đảo và affine làm cho quan hệ giữa
đầu vào và đầu ra phi tuyến, tạo tính confusion và ngăn không cho toàn bộ AES
trở thành một hệ phương trình tuyến tính đơn giản.

Trong RTL, S-box được mô tả bằng câu lệnh `case` chứa đủ 256 ánh xạ chuẩn. Cách
mô tả này rõ ràng, dễ đối chiếu với FIPS 197 và cho phép công cụ tổng hợp ánh xạ
sang LUT hoặc ROM tùy kiến trúc FPGA. Nếu đầu vào chứa `X/Z`, nhánh `default`
trả về `8'hxx` để lỗi chưa khởi tạo dễ xuất hiện trong mô phỏng.

### 6.2. Khối `aes_subbytes`

| Thuộc tính | Giá trị |
|---|---:|
| Đầu vào state | 128 bit |
| Đầu ra state | 128 bit |
| Số byte xử lý song song | 16 |
| Số instance `aes_sbox` mỗi khối | 16 |
| Loại logic | Tổ hợp |

SubBytes chia state 128 bit thành 16 byte và đưa từng byte qua một S-box độc
lập. Tất cả byte được thay thế song song trong cùng một chu kỳ tổ hợp:

\[
S'_{r,c}=SBOX(S_{r,c})
\]

SubBytes không trộn các byte với nhau; nhiệm vụ của nó là tạo phi tuyến. Việc
trộn và lan truyền ảnh hưởng giữa các vị trí được thực hiện bởi ShiftRows và
MixColumns ở các bước sau.

### 6.3. Khối `aes_shiftrows`

| Thuộc tính | Giá trị |
|---|---:|
| Đầu vào | 128 bit |
| Đầu ra | 128 bit |
| Loại logic | Hoán vị dây tổ hợp |

ShiftRows dịch vòng các byte trên từng hàng của state:

- Hàng 0: không dịch.
- Hàng 1: dịch vòng trái 1 byte.
- Hàng 2: dịch vòng trái 2 byte.
- Hàng 3: dịch vòng trái 3 byte.

Nếu state trước ShiftRows là:

\[
\begin{bmatrix}
s_{0,0}&s_{0,1}&s_{0,2}&s_{0,3}\\
s_{1,0}&s_{1,1}&s_{1,2}&s_{1,3}\\
s_{2,0}&s_{2,1}&s_{2,2}&s_{2,3}\\
s_{3,0}&s_{3,1}&s_{3,2}&s_{3,3}
\end{bmatrix}
\]

thì sau ShiftRows là:

\[
\begin{bmatrix}
s_{0,0}&s_{0,1}&s_{0,2}&s_{0,3}\\
s_{1,1}&s_{1,2}&s_{1,3}&s_{1,0}\\
s_{2,2}&s_{2,3}&s_{2,0}&s_{2,1}\\
s_{3,3}&s_{3,0}&s_{3,1}&s_{3,2}
\end{bmatrix}
\]

Khối này không thực hiện phép tính số học; RTL chỉ nối lại vị trí byte. Vai trò
của ShiftRows là đưa các byte vốn nằm trong cùng một cột sang các cột khác để
MixColumns ở round kế tiếp khuếch tán ảnh hưởng rộng hơn trên toàn state.

### 6.4. Khối `aes_mixcolumns`

| Thuộc tính | Giá trị |
|---|---:|
| Đầu vào | 128 bit |
| Đầu ra | 128 bit |
| Số cột xử lý song song | 4 |
| Kích thước mỗi cột | 32 bit = 4 byte |
| Số phép `xtime` cấu trúc mỗi khối | 16 |
| Loại logic | Tổ hợp trên `GF(2^8)` |

MixColumns xem mỗi cột gồm bốn byte là một vector và nhân vector đó với ma trận
cố định trong `GF(2^8)`:

\[
\begin{bmatrix}
r_0\\r_1\\r_2\\r_3
\end{bmatrix}
=
\begin{bmatrix}
02&03&01&01\\
01&02&03&01\\
01&01&02&03\\
03&01&01&02
\end{bmatrix}
\begin{bmatrix}
s_0\\s_1\\s_2\\s_3
\end{bmatrix}
\]

Tương đương:

\[
\begin{aligned}
r_0 &= 2s_0\oplus3s_1\oplus s_2\oplus s_3\\
r_1 &= s_0\oplus2s_1\oplus3s_2\oplus s_3\\
r_2 &= s_0\oplus s_1\oplus2s_2\oplus3s_3\\
r_3 &= 3s_0\oplus s_1\oplus s_2\oplus2s_3
\end{aligned}
\]

Phép nhân 2 được hiện thực bằng hàm `xtime`:

```text
xtime(a) = (a << 1) XOR 0x1B, nếu bit a[7] = 1
           (a << 1),            nếu bit a[7] = 0
```

Hằng số `0x1B` xuất hiện do phép rút gọn modulo đa thức `0x11B`; bit bậc tám
đã bị dịch ra ngoài byte nên phần XOR còn lại là `0x1B`. Phép nhân 3 được tính
bằng `xtime(a) XOR a`. Vì nhân với 1 chính là giữ nguyên byte, toàn bộ
MixColumns chỉ cần dịch, XOR và logic chọn theo bit cao, không cần bộ nhân số
học thông thường.

MixColumns tạo diffusion: thay đổi một byte đầu vào làm thay đổi cả bốn byte
trong cùng cột. Kết hợp với ShiftRows qua nhiều round, ảnh hưởng này lan ra toàn
bộ 16 byte của state.

### 6.5. Khối `aes_addroundkey`

| Thuộc tính | Giá trị |
|---|---:|
| Đầu vào state | 128 bit |
| Đầu vào round-key | 128 bit |
| Đầu ra | 128 bit |
| Phép toán | 128 XOR bit song song |
| Loại logic | Tổ hợp |

AddRoundKey thực hiện:

\[
state_{out}=state_{in}\oplus round\_key
\]

Đây là bước trực tiếp đưa thông tin bí mật của khóa vào quá trình mã hóa. XOR
có tính tự nghịch đảo, do đó cùng cấu trúc có thể dùng trong cả mã hóa và giải
mã. SubBytes, ShiftRows và MixColumns là các phép biến đổi cố định; nếu không
có AddRoundKey, chúng không tạo ra tính bí mật phụ thuộc khóa.

### 6.6. Khối `aes_round`

| Thuộc tính | Giá trị |
|---|---:|
| Đầu vào | state 128 bit + round-key 128 bit |
| Đầu ra | state 128 bit |
| Chuỗi xử lý | SubBytes → ShiftRows → MixColumns → AddRoundKey |
| Loại logic | Tổ hợp |

Khối này hiện thực normal round và được dùng cho round 1 đến round 13. Các tín
hiệu trung gian `state_out_subbytes`, `state_out_shiftrows` và
`state_out_mixcolumns` đều rộng 128 bit. Không có thanh ghi bên trong round;
state chỉ được chốt tại `state_reg` của top-level sau khi toàn bộ chuỗi tổ hợp
hoàn tất.

### 6.7. Khối `aes_roundlast`

| Thuộc tính | Giá trị |
|---|---:|
| Đầu vào | state 128 bit + round-key 128 bit |
| Đầu ra | state 128 bit |
| Chuỗi xử lý | SubBytes → ShiftRows → AddRoundKey |
| Khác normal round | Không có MixColumns |

Final round được tách thành module riêng để phản ánh trực tiếp cấu trúc FIPS
197. Trong top-level, `aes_round` và `aes_roundlast` đều tồn tại dưới dạng phần
cứng tổ hợp; bộ điều khiển chỉ chốt `normal_round_out` ở round 1–13 và chốt
`final_round_out` ở round 14.

### 6.8. Khối `aes256_key_expand_block`

| Thuộc tính | Giá trị |
|---|---:|
| Đầu vào khóa cửa sổ | 256 bit = 8 word |
| Đầu vào `rcon` | 8 bit |
| Đầu ra khóa cửa sổ kế tiếp | 256 bit = 8 word |
| Số S-box | 8 |
| Loại logic | Tổ hợp |

Khối nhận tám word cũ `w0` đến `w7` và sinh tám word mới `n0` đến `n7`.
Bốn S-box đầu thực hiện `SubWord(RotWord(w7))`; kết quả được XOR với Rcon để
tạo schedule core:

\[
T=SubWord(RotWord(w_7))\oplus(Rcon\ll24)
\]

Sau đó:

\[
\begin{aligned}
n_0&=w_0\oplus T\\
n_1&=w_1\oplus n_0\\
n_2&=w_2\oplus n_1\\
n_3&=w_3\oplus n_2
\end{aligned}
\]

AES-256 có bước SubWord bổ sung tại vị trí `i mod 8 = 4`, vì vậy bốn S-box còn
lại tính `SubWord(n3)`:

\[
\begin{aligned}
n_4&=w_4\oplus SubWord(n_3)\\
n_5&=w_5\oplus n_4\\
n_6&=w_6\oplus n_5\\
n_7&=w_7\oplus n_6
\end{aligned}
\]

Đây là điểm khác đáng chú ý của key schedule AES-256 so với AES-128. Phép
SubWord bổ sung làm tăng tính phi tuyến của quá trình sinh khóa cho cấu trúc
khóa tám word.

### 6.9. Khối `aes256_key_schedule`

| Thuộc tính | Giá trị |
|---|---:|
| Đầu vào khóa chính | 256 bit |
| Đầu ra | 1920 bit = 15 round-key |
| Số `aes256_key_expand_block` | 7 |
| Số S-box cấu trúc trong key schedule | 7 × 8 = 56 |
| Các Rcon sử dụng | `01, 02, 04, 08, 10, 20, 40` |
| Loại logic | Chuỗi tổ hợp |

Với AES-256, khóa chính cung cấp trực tiếp tám word đầu `w[0]` đến `w[7]`.
Key expansion cần tạo tổng cộng 60 word:

\[
w[0],w[1],...,w[59]
\]

Công thức tổng quát là:

```text
temp = w[i-1]

if i mod 8 == 0:
    temp = SubWord(RotWord(temp)) XOR Rcon[i/8]
else if i mod 8 == 4:
    temp = SubWord(temp)

w[i] = w[i-8] XOR temp
```

Round-key thứ `r` được ghép từ bốn word liên tiếp:

\[
RK_r=\{w[4r],w[4r+1],w[4r+2],w[4r+3]\},\quad0\le r\le14
\]

Bus `round_keys[1919:0]` đặt round-key 0 ở slice thấp nhất. Top-level chọn khóa
bằng biểu thức tương đương `round_keys[round_count*128 +: 128]`.

Bảy expand block tạo các cửa sổ `w[8:15]`, `w[16:23]`, ..., `w[56:63]`.
AES-256 chỉ cần đến `w[59]`, vì vậy `w[60]` đến `w[63]` được tính do cấu trúc
block 256 bit nhưng không được đưa vào 15 round-key. Đây là phần logic dư theo
cách tổ chức hiện tại và có thể tối ưu trong phiên bản sau.

Điểm quan trọng là key schedule hiện tại **không iterative theo clock**. Cả bảy
expand block được nối thành một chuỗi tổ hợp từ `key_reg`. Ưu điểm là round-key
nào cũng có sẵn mà không cần thêm chu kỳ sinh khóa. Nhược điểm là sử dụng nhiều
S-box và đường đến các round-key cuối đi qua chuỗi tổ hợp dài, có thể hạn chế
tần số clock sau synthesis/place-and-route.

### 6.10. Khối điều khiển và top-level `aes256_core`

Giao tiếp top-level:

| Cổng | Hướng | Độ rộng | Chức năng |
|---|---|---:|---|
| `clk` | Input | 1 bit | Clock hệ thống |
| `rst_n` | Input | 1 bit | Reset bất đồng bộ, tác động mức thấp |
| `start` | Input | 1 bit | Yêu cầu bắt đầu mã hóa khi core đang rảnh |
| `plaintext` | Input | 128 bit | Block dữ liệu đầu vào theo thứ tự hex NIST |
| `key` | Input | 256 bit | Khóa AES-256 theo thứ tự hex NIST |
| `ciphertext` | Output | 128 bit | Block dữ liệu đã mã hóa |
| `busy` | Output | 1 bit | Core đang xử lý, không nhận block mới |
| `done` | Output | 1 bit | Xung một chu kỳ báo ciphertext hợp lệ |

Các thanh ghi logic trong top-level:

| Thanh ghi | Độ rộng | Chức năng |
|---|---:|---|
| `key_reg` | 256 bit | Giữ khóa ổn định trong toàn bộ phép mã hóa |
| `state_reg` | 128 bit | Giữ state giữa các round |
| `round_count` | 4 bit | Đếm từ round 1 đến round 14 |
| `ciphertext` | 128 bit | Giữ kết quả đầu ra |
| `busy` | 1 bit | Trạng thái bận |
| `done` | 1 bit | Cờ hoàn tất dạng pulse |
| **Tổng** | **518 bit** | Số bit lưu trữ mô tả ở mức RTL |

Con số 518 bit là tổng độ rộng thanh ghi logic trước tối ưu synthesis, không
phải báo cáo sử dụng flip-flop cuối cùng. Bus 1920 bit `round_keys` và các state
trung gian là tín hiệu tổ hợp, không phải 1920 flip-flop.

Nguyên tắc điều khiển:

- Khi `rst_n = 0`, khóa, state, counter, ciphertext, `busy` và `done` được xóa.
- Mỗi chu kỳ bình thường, `done` mặc định được hạ về 0.
- `start` chỉ được nhận khi `busy = 0`.
- Nếu `start` xuất hiện trong lúc `busy = 1`, yêu cầu đó không được chốt như một
  transaction mới.
- Tại round 1–13, `state_reg` nhận kết quả normal round.
- Tại round 14, `state_reg` và `ciphertext` nhận kết quả final round, `busy = 0`
  và `done = 1`.

## 7. Trình tự hoạt động theo chu kỳ

| Mốc clock | Hoạt động | `round_count` sau cạnh clock | `busy` | `done` |
|---:|---|---:|---:|---:|
| Reset | Xóa trạng thái | 0 | 0 | 0 |
| T0 | Nhận `start`, chốt khóa, AddRoundKey ban đầu | 1 | 1 | 0 |
| T1 | Normal round 1 | 2 | 1 | 0 |
| T2 | Normal round 2 | 3 | 1 | 0 |
| ... | ... | ... | 1 | 0 |
| T13 | Normal round 13 | 14 | 1 | 0 |
| T14 | Final round 14, cập nhật ciphertext | 0 | 0 | 1 |
| T15 | Có thể nhận block tiếp theo | 1 nếu có `start` | 1 nếu nhận | 0 |

Vì T0 đã thực hiện AddRoundKey ban đầu và T1–T14 thực hiện 14 round, testbench
đo được `done` sau 14 chu kỳ xử lý kể từ cạnh đã nhận `start`. Hai lần nhận
`start` hợp lệ gần nhất cách nhau 15 chu kỳ.

## 8. Kích thước cấu trúc ở mức RTL

Bảng sau mô tả số instance trước synthesis. Công cụ có thể gộp, chia sẻ hoặc
ánh xạ lại logic nên đây không phải số LUT/FF vật lý cuối cùng.

| Cấu trúc | Số instance |
|---|---:|
| `aes256_core` | 1 |
| `aes256_key_schedule` | 1 |
| `aes256_key_expand_block` | 7 |
| S-box trong key schedule | 56 |
| `aes_round` | 1 |
| `aes_roundlast` | 1 |
| `aes_subbytes` trong hai đường round | 2 |
| S-box trong hai đường round | 32 |
| **Tổng S-box cấu trúc** | **88** |
| `aes_mixcolumns` | 1 |
| `aes_shiftrows` | 2 |
| `aes_addroundkey` trong hai đường round | 2 |

So với kiến trúc unroll 14 round, datapath hiện tại chỉ có một normal-round và
một final-round, không nhân bản 13 normal-round. Tuy nhiên, do normal-round và
final-round tồn tại đồng thời, số S-box datapath là 32 chứ không phải 16. Ngoài
ra key schedule tổ hợp chứa 56 S-box. Vì thế hướng tối ưu diện tích tiếp theo có
thể là:

1. Chia sẻ SubBytes và ShiftRows giữa normal round và final round, bypass
   MixColumns khi `round_count = 14`.
2. Sinh round-key on-the-fly theo từng chu kỳ để thay chuỗi 7 expand block bằng
   một khối key expansion hồi tiếp.
3. Chỉ tạo bốn word cuối `w[56:59]` thay vì tính dư đến `w[63]`.
4. Cân nhắc S-box dùng BRAM/ROM hoặc S-box logic tổng hợp tùy mục tiêu FPGA.

Muốn báo cáo chính xác số LUT, FF, BRAM, công suất và tần số cực đại cần chọn rõ
FPGA part, ràng buộc clock và chạy synthesis/place-and-route. Không nên lấy số
tài nguyên của một part rồi xem đó là thuộc tính cố định của thuật toán.

## 9. Đặc điểm của kiến trúc không pipeline

### 9.1. Ưu điểm

- Datapath round được tái sử dụng qua nhiều chu kỳ, nhỏ hơn kiến trúc unroll 14
  round có một phần cứng riêng cho mỗi round.
- Điều khiển đơn giản, độ trễ cố định và dễ quan sát state theo từng round.
- Phù hợp với hệ thống chỉ cần xử lý một block tại một thời điểm hoặc ưu tiên
  diện tích hơn thông lượng cực đại.
- Việc kiểm chứng thuận lợi vì thứ tự round bám sát pseudocode của FIPS 197.

### 9.2. Hạn chế

- Không thể nhận một block mới ở mỗi clock như pipeline đầy đủ.
- Thông lượng bị giới hạn bởi khoảng cách tối thiểu 15 chu kỳ giữa hai block.
- Key schedule tổ hợp hiện tại có đường logic dài đến round-key cuối.
- Hai đường normal round và final round làm trùng lặp 16 S-box cùng một số logic
  hoán vị/XOR.
- S-box dạng bảng có thể chiếm nhiều LUT nếu công cụ không ánh xạ theo mong
  muốn.

Kiến trúc vì vậy nên được gọi chính xác là **iterative datapath với key schedule
tổ hợp unrolled**, không nên mô tả toàn bộ thiết kế là iterative hoàn toàn.

## 10. Lý do chọn AES-256 thay vì AES-128 hoặc AES-192

### 10.1. So sánh ba biến thể AES

| Thuộc tính | AES-128 | AES-192 | AES-256 |
|---|---:|---:|---:|
| Kích thước block | 128 bit | 128 bit | 128 bit |
| Kích thước khóa | 128 bit | 192 bit | 256 bit |
| `Nk` | 4 word | 6 word | 8 word |
| Số round `Nr` | 10 | 12 | 14 |
| Số round-key | 11 | 13 | 15 |
| Không gian vét cạn lý tưởng | `2^128` | `2^192` | `2^256` |
| Chi phí tính toán tương đối | Thấp nhất | Trung gian | Cao nhất |
| Độ trễ nếu dùng cùng kiến trúc iterative | Ngắn nhất | Trung gian | Dài nhất |

AES-256 được chọn trong đề tài vì các lý do sau:

**Thứ nhất, biên an toàn khóa lớn nhất.** Tấn công vét cạn lý tưởng lên khóa
256 bit cần kiểm tra tới `2^256` khả năng, lớn hơn rất nhiều so với `2^128` của
AES-128 và `2^192` của AES-192. AES-128 hiện vẫn được xem là an toàn cho rất
nhiều ứng dụng; lựa chọn AES-256 không có nghĩa AES-128 đã bị phá. Mục tiêu ở
đây là tạo biên an toàn dài hạn lớn hơn khi chi phí thêm 4 round có thể chấp
nhận được.

**Thứ hai, dự phòng tốt hơn trong mô hình tấn công lượng tử lý tưởng.** Thuật
toán Grover có thể giảm bậc phức tạp của tìm kiếm khóa không cấu trúc từ khoảng
`2^k` xuống khoảng `2^(k/2)` truy vấn. Theo cách ước lượng lý tưởng này,
AES-128 có biên tương đương khoảng 64 bit còn AES-256 khoảng 128 bit. Đây không
phải khẳng định rằng máy lượng tử thực tế hiện có thể phá AES: chi phí mạch,
sửa lỗi lượng tử, độ sâu và số lần thực hiện oracle là cực lớn. Tuy nhiên,
AES-256 cho dư địa tốt hơn đối với dữ liệu cần bảo mật lâu dài.

**Thứ ba, phù hợp mục tiêu nghiên cứu phần cứng bảo mật cao.** Đề tài cần thể
hiện đầy đủ trường hợp key schedule phức tạp nhất của AES, gồm khóa tám word,
14 round và nhánh `SubWord` bổ sung tại `i mod 8 = 4`. Hoàn thành AES-256 chứng
minh datapath và bộ sinh khóa xử lý được biến thể có khóa dài nhất trong FIPS
197.

**Thứ tư, AES-192 là lựa chọn trung gian nhưng ít tạo khác biệt rõ ràng cho mục
tiêu đề tài.** AES-192 giảm hai round so với AES-256 và có biên khóa lớn hơn
AES-128, nhưng giao tiếp khóa 192 bit kém tự nhiên hơn trên nhiều datapath chia
theo 128/256 bit. Nếu đã chấp nhận chi phí cao hơn AES-128 để ưu tiên biên an
toàn dài hạn, AES-256 mang lại mức khóa tối đa của chuẩn với thêm hai round so
với AES-192.

**Thứ năm, chi phí tăng thêm vẫn phù hợp kiến trúc iterative.** So với AES-128,
AES-256 tăng từ 10 lên 14 round. Với kiến trúc này, chi phí thể hiện chủ yếu ở
độ trễ và key schedule; không cần nhân bản thêm bốn datapath round vì cùng
normal-round được tái sử dụng theo thời gian.

### 10.2. Các đánh đổi cần nhìn nhận

AES-256 không phải lựa chọn tối ưu tuyệt đối cho mọi hệ thống:

- AES-128 có ít round hơn nên thường nhanh hơn, tiêu thụ ít năng lượng và tài
  nguyên key schedule hơn.
- AES-192 là điểm cân bằng nếu yêu cầu chính sách bắt buộc khóa lớn hơn 128 bit
  nhưng không muốn chi phí đầy đủ của AES-256.
- Khóa 256 bit không làm block AES lớn hơn 128 bit. Các giới hạn liên quan đến
  kích thước block và birthday bound vẫn phải được xử lý bằng mode of operation
  và giới hạn lượng dữ liệu mã hóa dưới một khóa.
- An toàn hệ thống không chỉ phụ thuộc độ dài khóa. Quản lý khóa, nonce/IV,
  xác thực, random number generator, side-channel và lỗi triển khai có thể quan
  trọng hơn việc chọn 128 hay 256 bit.

Do đó, kết luận hợp lý cho đề tài là: **AES-256 được chọn để ưu tiên biên an
toàn dài hạn và nghiên cứu biến thể AES phức tạp nhất, trong khi chấp nhận tăng
độ trễ, diện tích key schedule và công suất so với AES-128/192.**

## 11. Kiểm chứng chức năng

Thiết kế được compile và mô phỏng bằng Questa Altera Starter FPGA Edition 2025.2
đi kèm Quartus. Quá trình compile kết thúc với 0 lỗi và 0 cảnh báo. Năm vector
kiểm thử đều cho ciphertext chính xác và độ trễ 14 chu kỳ.

| Test | Nguồn | Plaintext | Ciphertext mong đợi/thực tế | Kết quả |
|---:|---|---|---|---|
| 1 | FIPS 197 C.3 | `00112233445566778899aabbccddeeff` | `8ea2b7ca516745bfeafc49904b496089` | PASS |
| 2 | SP 800-38A | `6bc1bee22e409f96e93d7e117393172a` | `f3eed1bdb5d2a03c064b5a7e3db181f8` | PASS |
| 3 | SP 800-38A | `ae2d8a571e03ac9c9eb76fac45af8e51` | `591ccb10d410ed26dc5ba74a31362870` | PASS |
| 4 | SP 800-38A | `30c81c46a35ce411e5fbc1191a0a52ef` | `b6ed21b99ca6f4f9f153e7b1beafed1d` | PASS |
| 5 | SP 800-38A | `f69f2445df4f9b17ad2b417be66c3710` | `23304b7a39f9f3ff067d8d8f9e24ecc7` | PASS |

Khóa của test 1 là:

```text
000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
```

Bốn test SP 800-38A dùng khóa:

```text
603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4
```

Mô phỏng kết thúc tại 786 ns với thông báo `ALL TESTS PASSED (5/5)`. Kết quả
Questa trùng với lần chạy đối chiếu bằng Icarus Verilog 12.0. Vivado Simulator
2025.2 cũng phân tích và elaborate thành công toàn bộ SystemVerilog; kernel XSIM
trên môi trường RHEL 10.2 gặp lỗi runtime trước time 0 nên kết quả mô phỏng
vendor cuối cùng được lấy từ Questa-Intel FPGA thuộc bộ Quartus.

## 12. Đánh giá và hướng phát triển

Thiết kế đã hoàn thành đúng chức năng mã hóa AES-256 và có giao tiếp điều khiển
rõ ràng. Việc chia nhỏ module theo từng phép biến đổi giúp dễ kiểm thử, dễ tái
sử dụng và thuận lợi cho việc so sánh với FIPS 197. Kiến trúc iterative làm
giảm mức nhân bản datapath so với unrolled pipeline, phù hợp mục tiêu thiết kế
không pipeline.

Các hướng phát triển nên ưu tiên:

1. **Synthesis trên FPGA đích:** chọn part cụ thể, tạo clock constraint và báo
   cáo LUT, FF, BRAM, công suất, critical path, WNS và Fmax.
2. **Key expansion on-the-fly:** sinh round-key theo chu kỳ để giảm 56 S-box của
   key schedule tổ hợp và rút ngắn đường khóa.
3. **Chia sẻ final-round:** dùng một datapath SubBytes/ShiftRows và mux bypass
   MixColumns ở round 14 để giảm 16 S-box trùng lặp.
4. **Hỗ trợ decrypt:** bổ sung InvSubBytes, InvShiftRows, InvMixColumns và thứ tự
   sử dụng round-key ngược.
5. **Tích hợp mode an toàn:** ưu tiên authenticated encryption như AES-GCM khi
   xây dựng hệ thống hoàn chỉnh; quản lý nonce phải được thiết kế đúng.
6. **Bảo vệ side-channel:** cân nhắc masking, hiding, cân bằng switching,
   zeroization và kiểm thử leakage nếu khóa được dùng trong môi trường đối
   kháng vật lý.
7. **Verification mở rộng:** random test đối chiếu với software golden model,
   assertion cho giao thức `start/busy/done`, test reset giữa transaction và
   formal verification cho từng phép biến đổi.

## 13. Kết luận

Lõi AES-256 được xây dựng theo kiến trúc iterative không pipeline ở datapath.
Một state 128 bit được hồi tiếp qua normal-round trong 13 chu kỳ và final-round
trong chu kỳ thứ 14, sau AddRoundKey ban đầu tại thời điểm nhận `start`. Mỗi
normal round gồm SubBytes, ShiftRows, MixColumns và AddRoundKey; final round bỏ
MixColumns. Khóa 256 bit được mở rộng thành 15 round-key 128 bit bằng key
schedule AES-256 tổ hợp.

Thiết kế đạt đúng kết quả cho 5/5 vector FIPS/NIST trên Questa-Intel FPGA 2025.2
với 0 lỗi và 0 cảnh báo. AES-256 được chọn vì cung cấp biên an toàn khóa lớn,
phù hợp dữ liệu cần bảo mật dài hạn và cho phép nghiên cứu đầy đủ biến thể AES
có key schedule phức tạp nhất. Đổi lại, thiết kế cần 14 round, nhiều logic sinh
khóa hơn và có độ trễ/công suất lớn hơn AES-128 hoặc AES-192. Đây là một đánh
đổi có chủ đích, phù hợp mục tiêu ưu tiên an toàn và nghiên cứu kiến trúc phần
cứng AES-256.

## Tài liệu tham khảo

[1] National Institute of Standards and Technology, *Advanced Encryption
Standard (AES)*, FIPS 197-upd1, cập nhật ngày 09/05/2023,
https://doi.org/10.6028/NIST.FIPS.197-upd1. Bản PDF được lưu tại
`doc/NIST.FIPS.197-upd1.pdf`.

[2] National Institute of Standards and Technology, *Recommendation for Block
Cipher Modes of Operation: Methods and Techniques*, NIST SP 800-38A,
https://doi.org/10.6028/NIST.SP.800-38A.

[3] L. K. Grover, “A Fast Quantum Mechanical Algorithm for Database Search,”
*Proceedings of the 28th Annual ACM Symposium on Theory of Computing*, 1996.

[4] Mã nguồn SystemVerilog và testbench của thiết kế tại `rtl/rtl_backup`.

[5] Log mô phỏng Questa-Intel FPGA tại
`rtl/rtl_backup/build_questa/transcript`.
