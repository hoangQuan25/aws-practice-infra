# Section 1 — Bài 2: Ôn IPv4, thiết kế VPC và quy hoạch dải IP

## Mục tiêu bài học

Sau bài này, người học có thể:

- Đọc một IPv4 CIDR và xác định network address, prefix length, tổng số địa chỉ và phạm vi địa chỉ của mạng.
- Giải thích sự khác nhau giữa VPC, subnet, Availability Zone và route table.
- Phân biệt public subnet và private subnet dựa trên cấu hình định tuyến thay vì chỉ dựa vào tên hoặc dải IP.
- Chia một dải VPC thành các subnet không chồng lấn, có dự trữ chỗ cho việc tăng trưởng và phân bố qua nhiều Availability Zone.
- Đề xuất các dải IP riêng biệt cho dev và prod, đồng thời kiểm tra xung đột với mạng đang tồn tại, mạng on-premises và các VPC khác.
- Dùng AWS Management Console ở chế độ chỉ đọc để quan sát VPC, CIDR, subnet, Availability Zone và route table.

## 1. Bối cảnh và vấn đề

Trước khi triển khai máy chủ, load balancer hoặc database, cần quyết định các tài nguyên đó sẽ nằm trong mạng nào và nhận địa chỉ IP từ dải nào. Trong AWS, Amazon Virtual Private Cloud (Amazon VPC) cung cấp một mạng ảo được cô lập về mặt logic trong một AWS Region. Người thiết kế chọn dải IPv4 cho VPC, chia dải đó thành các subnet, rồi cấu hình đường đi giữa subnet và các mạng khác.

Quyết định CIDR thường được đưa ra sớm nhưng tồn tại lâu. Nếu dev, prod, mạng văn phòng và mạng on-premises sử dụng các dải địa chỉ chồng lấn, việc kết nối bằng VPN, VPC peering hoặc AWS Transit Gateway có thể khó hoặc không thể định tuyến như dự kiến. Khi đó, việc đổi địa chỉ có thể ảnh hưởng đến nhiều tài nguyên, cấu hình, firewall rule và hệ thống phụ thuộc.

Ví dụ, một ứng dụng e-commerce có thể cần:

- Các subnet public để đặt Application Load Balancer (ALB) nhận traffic từ Internet.
- Các subnet private cho ECS tasks hoặc EC2 instances.
- Các subnet riêng cho database, không mở đường truy cập trực tiếp từ Internet.
- Nhiều Availability Zone (AZ) để tăng khả năng chịu lỗi.

Muốn bố trí các thành phần này hợp lý, cần lập kế hoạch địa chỉ trước: mỗi VPC nhận một CIDR riêng; mỗi subnet nằm hoàn toàn trong một AZ; các subnet không chồng lấn; và còn đủ không gian địa chỉ cho dịch vụ hiện tại lẫn tăng trưởng.

## 2. Khái niệm và thành phần cốt lõi

### IPv4 address và CIDR notation

IPv4 address có độ dài 32 bit, thường được viết thành bốn số thập phân ngăn bằng dấu chấm, ví dụ `10.20.4.15`. Mỗi phần có giá trị từ 0 đến 255 vì mỗi phần biểu diễn 8 bit.

CIDR là viết tắt của **Classless Inter-Domain Routing**. CIDR notation biểu diễn một dải địa chỉ bằng địa chỉ bắt đầu và prefix length, ví dụ `10.20.0.0/16`:

- `10.20.0.0` là địa chỉ bắt đầu của dải trong ví dụ này.
- `/16` nghĩa là 16 bit đầu tiên cố định để biểu diễn phần network.
- 32 − 16 = 16 bit còn lại dùng để biểu diễn các địa chỉ bên trong dải.
- Tổng số địa chỉ của dải là `2^(32 - prefix length)`, nên `/16` có `2^16 = 65,536` địa chỉ IPv4.

Prefix length càng nhỏ thì dải càng lớn; prefix length càng lớn thì dải càng nhỏ:

```text
10.20.0.0/16
└── dải lớn, có nhiều địa chỉ hơn

10.20.1.0/24
└── dải nhỏ hơn, thường có thể dùng làm một subnet

10.20.1.0/28
└── dải nhỏ hơn nữa, chỉ có 16 địa chỉ tổng cộng
```

Ký hiệu CIDR phải được căn theo ranh giới prefix. Ví dụ `/24` có kích thước khối 256 địa chỉ ở phần cuối, vì vậy `10.20.1.0/24` là một dải căn đúng; `10.20.1.12/24` không phải cách biểu diễn network address chuẩn của subnet đó.

### Network address, host address và broadcast address

Một CIDR đại diện cho cả một khối địa chỉ, không chỉ một địa chỉ đơn lẻ:

- **Network address** định danh khối mạng.
- Các địa chỉ còn lại thuộc khối đó có thể là host address, tùy quy tắc của nền tảng sử dụng mạng.
- Trong mô hình IPv4 subnet truyền thống, địa chỉ cuối thường được gọi là broadcast address.

AWS dành riêng một số địa chỉ trong mỗi IPv4 subnet cho hoạt động mạng của nền tảng. Vì vậy, số địa chỉ host có thể sử dụng trong subnet AWS ít hơn tổng số địa chỉ của CIDR. Không nên lấy toàn bộ số địa chỉ toán học để lập công suất workload.

### Các dải IPv4 private thường dùng

RFC 1918 định nghĩa ba khối địa chỉ IPv4 private thường dùng trong mạng nội bộ:

| Dải private | Prefix | Tổng địa chỉ | Ví dụ các mạng con |
|---|---:|---:|---|
| `10.0.0.0` – `10.255.255.255` | `/8` | 16,777,216 | `10.20.0.0/16`, `10.30.0.0/16` |
| `172.16.0.0` – `172.31.255.255` | `/12` | 1,048,576 | `172.20.0.0/16` |
| `192.168.0.0` – `192.168.255.255` | `/16` | 65,536 | `192.168.10.0/24` |

Đây là các lựa chọn phổ biến, không phải khuyến nghị tự động cho mọi môi trường. Trước khi chọn dải cho VPC, phải kiểm tra mạng hiện có của tổ chức, VPN, các VPC khác, môi trường cloud khác và dải mà ISP hoặc nhà cung cấp đã sử dụng. Dùng một dải private không đảm bảo nó không bị trùng với mạng nội bộ.

### Amazon VPC

Amazon VPC là mạng ảo nằm trong một AWS Region. Khi tạo VPC, người thiết kế chọn một hoặc nhiều IPv4 CIDR block phù hợp với giới hạn hiện hành của AWS. VPC là phạm vi mạng lớn hơn; các subnet được tạo bên trong VPC để bố trí tài nguyên theo tầng, vùng sẵn sàng hoặc chính sách định tuyến.

Các tài nguyên trong một VPC thường giao tiếp qua địa chỉ private IP theo cấu hình mạng. Muốn đi đến mạng khác, chẳng hạn Internet, mạng on-premises hoặc VPC khác, cần đường kết nối và route thích hợp; chỉ có CIDR không tự tạo ra kết nối.

### Subnet và Availability Zone

Subnet là một phần của CIDR VPC, dùng để phân chia không gian địa chỉ và bố trí tài nguyên. Trong Amazon VPC:

- Mỗi subnet thuộc về một **Availability Zone** cụ thể.
- Một subnet không trải rộng qua nhiều AZ.
- Một AZ có thể chứa nhiều subnet.
- Các subnet trong cùng một VPC không được có CIDR IPv4 chồng lấn.

AZ là vị trí hạ tầng cô lập trong một Region. Tạo các subnet ở nhiều AZ cho phép bố trí workload ở nhiều vị trí độc lập hơn, nhưng bản thân việc có subnet ở nhiều AZ không tự làm ứng dụng có tính sẵn sàng cao. Ứng dụng, load balancer, database, routing và cơ chế failover cũng phải được cấu hình phù hợp.

### Public subnet và private subnet

Tên “public” hoặc “private” không được quyết định bởi việc CIDR là `10.x.x.x` hay `192.168.x.x`. Đây là cách gọi theo khả năng định tuyến:

- Một subnet thường được gọi là **public subnet** khi route table liên kết với subnet có route trực tiếp đến Internet Gateway. Để một tài nguyên trong subnet có thể giao tiếp trực tiếp với Internet, tài nguyên đó cũng cần địa chỉ public phù hợp cùng security group và network ACL cho phép traffic cần thiết.
- Một subnet thường được gọi là **private subnet** khi không có route trực tiếp từ subnet đó ra Internet qua Internet Gateway. Nó có thể có route ra ngoài qua NAT Gateway, VPC endpoint hoặc các kết nối riêng khác.

Route table quyết định next hop cho các dải đích. Security group và network ACL điều khiển luồng được phép; chúng không thay thế route table. Một subnet có route đến Internet Gateway nhưng tài nguyên không có địa chỉ public phù hợp chưa chắc có thể giao tiếp hai chiều với Internet như dự kiến.

### Bảng phân biệt phạm vi mạng

| Thành phần | Phạm vi | Quan hệ với CIDR/AZ | Vai trò chính |
|---|---|---|---|
| AWS Region | Khu vực địa lý gồm nhiều AZ | Chứa VPC; VPC không trải qua nhiều Region | Phạm vi triển khai dịch vụ theo vùng |
| VPC | Mạng ảo trong một Region | Có một hoặc nhiều CIDR block | Ranh giới mạng lớn để chứa subnet và tài nguyên |
| Availability Zone | Vị trí hạ tầng cô lập trong Region | Subnet được tạo trong một AZ | Cung cấp vị trí triển khai độc lập hơn để thiết kế HA |
| Subnet | Phân đoạn địa chỉ trong VPC | Một CIDR không chồng lấn, nằm trong một AZ | Bố trí tài nguyên và gắn route table |
| Route table | Tập các tuyến đường | Có thể liên kết với một hoặc nhiều subnet | Chọn next hop cho traffic đi đến destination CIDR |

## 3. Cách hoạt động: từ CIDR đến VPC topology

Quy trình thiết kế bắt đầu từ nhu cầu kết nối và mở rộng, sau đó mới chia địa chỉ và chọn nơi đặt tài nguyên:

```text
Kiểm kê mạng hiện có và nhu cầu kết nối
                  │
                  ▼
Chọn CIDR không chồng lấn cho từng VPC
                  │
                  ▼
Chia CIDR VPC thành các CIDR subnet
                  │
                  ▼
Gán mỗi subnet vào một AZ và một tầng ứng dụng
                  │
                  ▼
Thiết kế route table, security group và kết nối
                  │
                  ▼
Triển khai và xác minh topology trên AWS
```

### Bước 1: Kiểm kê dải địa chỉ cần tương thích

Trước khi chọn CIDR, lập danh sách các dải đang hoặc có thể cần định tuyến với VPC:

- Mạng văn phòng và mạng on-premises.
- Các VPC hiện tại trong cùng account hoặc tổ chức.
- VPC ở AWS account khác mà có thể kết nối về sau.
- Các mạng đang dùng qua VPN, Transit Gateway, peering hoặc hệ thống khác.
- Những mạng dự kiến trong kế hoạch mở rộng.

CIDR overlap không phải lúc nào cũng ngăn hai mạng hoạt động riêng biệt, nhưng thường gây vấn đề khi cần định tuyến trực tiếp giữa chúng. Vì vậy, phải xem yêu cầu kết nối tương lai thay vì chỉ kiểm tra xem VPC mới có chạy được độc lập hay không.

### Bước 2: Chọn CIDR cho từng VPC

Chọn dải có đủ chỗ cho subnet và tăng trưởng, nhưng không quá lớn hoặc trùng với dải khác. Một quy ước minh họa cho bài thực hành:

```text
Dev VPC:  10.20.0.0/16
Prod VPC: 10.30.0.0/16
```

Hai CIDR trên không chồng lấn với nhau và thuận tiện để người học nhận biết môi trường. Chúng chỉ là ví dụ cho lab. Trước khi sử dụng thực tế, cần xác nhận chúng không chồng lấn với các mạng hiện hữu hoặc mạng dự kiến kết nối.

### Bước 3: Chia VPC thành các subnet

Subnet CIDR phải nằm hoàn toàn bên trong VPC CIDR và không chồng lấn với bất kỳ subnet nào khác trong cùng VPC. Một sơ đồ dự trữ địa chỉ minh họa cho hai AZ:

| Môi trường | AZ | Tầng subnet | CIDR minh họa |
|---|---|---|---|
| Dev | AZ-a | Public | `10.20.0.0/24` |
| Dev | AZ-b | Public | `10.20.1.0/24` |
| Dev | AZ-a | Application private | `10.20.10.0/24` |
| Dev | AZ-b | Application private | `10.20.11.0/24` |
| Dev | AZ-a | Data private | `10.20.20.0/24` |
| Dev | AZ-b | Data private | `10.20.21.0/24` |
| Prod | AZ-a | Public | `10.30.0.0/24` |
| Prod | AZ-b | Public | `10.30.1.0/24` |
| Prod | AZ-a | Application private | `10.30.10.0/24` |
| Prod | AZ-b | Application private | `10.30.11.0/24` |
| Prod | AZ-a | Data private | `10.30.20.0/24` |
| Prod | AZ-b | Data private | `10.30.21.0/24` |

Mục đích của sơ đồ không phải yêu cầu tạo ngay toàn bộ các subnet. Đây là một kế hoạch đánh địa chỉ ban đầu để minh họa cách giữ các tầng và môi trường tách biệt. Số lượng subnet, kích thước CIDR, số AZ và vị trí workload cần được chọn theo dịch vụ, yêu cầu sẵn sàng, lưu lượng và chi phí.

### Bước 4: Gắn subnet với AZ và route table

Sau khi xác định CIDR:

1. Gán từng subnet cho một AZ cụ thể trong Region đã chọn.
2. Liên kết subnet với route table phù hợp.
3. Định nghĩa route theo destination CIDR và next hop, chẳng hạn local route trong VPC, Internet Gateway hoặc NAT Gateway.
4. Dùng security group và network ACL để kiểm soát luồng theo vai trò của tài nguyên.
5. Xác minh đường đi cả chiều đi và chiều về; route một chiều hoặc rule không tương thích có thể khiến kết nối thất bại.

Bài này tập trung vào địa chỉ và cấu trúc mạng; cách cấu hình Internet Gateway, NAT Gateway, security group và network ACL sẽ được học ở các bài tiếp theo.

## 4. Tư duy kiến trúc, bảo mật, chi phí và đánh đổi

### Tính sẵn sàng và khả năng phục hồi

VPC có phạm vi Region, nhưng subnet thuộc một AZ. Muốn bố trí workload trên nhiều AZ, cần tạo subnet riêng cho từng AZ với các CIDR không chồng lấn. Điều này tạo nền tảng để một số loại workload phân tán qua AZ; nó không tự động nhân bản ứng dụng hoặc dữ liệu.

Kế hoạch IP nên tính đến cách dịch vụ sử dụng subnet và khả năng tăng trưởng. Nếu subnet quá nhỏ, dịch vụ có thể không còn địa chỉ để tạo thêm interface hoặc scale. Một số dịch vụ có yêu cầu về số lượng địa chỉ trống hoặc kích thước subnet; cần kiểm tra tài liệu dịch vụ trước khi chốt thiết kế. Ví dụ, ALB triển khai trong subnet cần đủ không gian địa chỉ cho hoạt động và scale của load balancer; cấu hình subnet quá nhỏ có thể làm giảm khả năng mở rộng hoặc không đáp ứng yêu cầu hiện hành của dịch vụ.

### Bảo mật

Phân chia public, application-private và data-private subnet giúp thể hiện ranh giới mạng và hỗ trợ áp dụng routing/security rules phù hợp. Tuy nhiên:

- Tên subnet không tự tạo bảo mật; route table, security group, network ACL, địa chỉ public và policy dịch vụ quyết định hành vi thực tế.
- Không đặt database trong subnet có đường định tuyến public nếu database không cần được truy cập trực tiếp từ Internet.
- Dải CIDR không phải một firewall. Việc hai resource thuộc CIDR private không tự ngăn hoặc cho phép giao tiếp giữa chúng.
- Tách CIDR dev/prod giúp tránh nhầm lẫn và hỗ trợ kết nối riêng biệt, nhưng không thay thế việc tách account, IAM, route và state.
- Không chia sẻ sơ đồ mạng nội bộ, IP nhạy cảm hoặc cấu hình VPN công khai nếu chính sách tổ chức không cho phép.

### Chi phí

Chọn CIDR hoặc tạo VPC/subnet tự nó không giống việc chạy compute/database có tính phí, nhưng các thành phần mạng và lưu lượng liên quan có thể phát sinh chi phí. NAT Gateway thường có phí theo thời gian và dữ liệu xử lý; data transfer, public IPv4 address hoặc các dịch vụ kết nối khác cũng có thể ảnh hưởng hóa đơn theo chính sách giá hiện hành.

Bài thực hành trong tài liệu này chỉ lập sơ đồ và tính toán trên giấy hoặc trong file cục bộ; không tạo VPC, NAT Gateway hay tài nguyên AWS khác. Khi bắt đầu triển khai ở bài lab tích hợp, phải ước tính chi phí trước, đặc biệt nếu bật NAT Gateway hoặc tài nguyên chạy liên tục.

### Lựa chọn kiến trúc và đánh đổi

- **Một CIDR lớn cho VPC:** Dễ dự trữ subnet mới và thường thuận tiện cho kế hoạch tăng trưởng, nhưng cần quản lý phân vùng địa chỉ chặt để không làm lãng phí không gian hoặc tạo ra sơ đồ khó hiểu.
- **CIDR nhỏ cho VPC:** Có thể phù hợp với môi trường giới hạn phạm vi, nhưng thiếu chỗ khi thêm AZ, tầng ứng dụng hoặc dịch vụ cần nhiều địa chỉ.
- **Subnet theo tầng ứng dụng:** Tách public, application và data giúp gán routing và kiểm soát truy cập rõ ràng; đổi lại cần quy hoạch nhiều subnet, route table và quy tắc bảo mật hơn.
- **Subnet theo AZ:** Tạo điều kiện bố trí workload qua nhiều AZ; đổi lại cần cấp subnet CIDR đủ nhất quán cho từng AZ và cấu hình resource/service tương ứng.
- **Dev và prod dùng CIDR không chồng lấn:** Giúp kết nối mạng, phân tích route và vận hành an toàn hơn; cần thống nhất quy hoạch ở cấp tổ chức để tránh nhiều nhóm tự chọn dải trùng nhau.
- **Tái sử dụng dải CIDR sau khi xóa VPC:** Có thể tận dụng không gian địa chỉ, nhưng cần cập nhật inventory và bảo đảm không còn hệ thống, state hoặc cấu hình kết nối tham chiếu dải cũ.

### Bảng tính số địa chỉ IPv4 trong subnet AWS

| Prefix | Tổng số địa chỉ IPv4 | Số địa chỉ AWS giữ lại | Số địa chỉ còn lại trong subnet AWS |
|---|---:|---:|---:|
| `/16` | 65,536 | 5 | 65,531 |
| `/20` | 4,096 | 5 | 4,091 |
| `/24` | 256 | 5 | 251 |
| `/27` | 32 | 5 | 27 |
| `/28` | 16 | 5 | 11 |

AWS giữ lại 5 địa chỉ IPv4 trong mỗi subnet: bốn địa chỉ đầu tiên và địa chỉ cuối cùng của subnet. Vì vậy, subnet `/28` có 16 địa chỉ toán học nhưng chỉ 11 địa chỉ có thể dùng cho thiết bị/resource trong subnet theo quy tắc này. Các giới hạn và yêu cầu của từng dịch vụ có thể làm số địa chỉ thực tế còn khả dụng thấp hơn nữa; hãy xác minh tài liệu AWS trước khi chọn kích thước subnet.

### Tính kích thước CIDR

Với IPv4:

```text
Số bit host = 32 - prefix length
Tổng số địa chỉ = 2^(số bit host)
Địa chỉ còn lại trong subnet AWS = tổng số địa chỉ - 5
```

Ví dụ với `10.20.10.0/24`:

```text
Số bit host = 32 - 24 = 8
Tổng địa chỉ = 2^8 = 256
Địa chỉ còn lại theo quy tắc AWS = 256 - 5 = 251
```

Đây là số địa chỉ còn lại sau khi trừ phần AWS giữ lại, không phải cam kết rằng mọi dịch vụ đều có thể dùng toàn bộ số đó. Resource, interface hoặc dịch vụ AWS có thể tiêu thụ địa chỉ theo cách riêng.

## 5. Quan sát trên AWS Management Console

Phần này chỉ xem cấu hình VPC hiện có. Nếu tài khoản mới chưa có VPC tùy chỉnh, hãy xem default VPC ở chế độ chỉ đọc; không tạo, sửa hoặc xóa mạng. Bố cục menu có thể thay đổi theo giao diện AWS, nên dùng thanh tìm kiếm để mở dịch vụ **VPC** nếu tên mục không giống mô tả.

1. **Xác nhận account và Region.** Đăng nhập bằng danh tính được cấp, xác nhận AWS account và Region đang chọn. VPC thuộc một Region, vì vậy nếu đổi Region có thể thấy một tập VPC khác.
2. **Mở danh sách VPC.** Trong dịch vụ VPC, mở **Your VPCs** hoặc danh sách VPC tương đương. Chọn một VPC bạn được phép xem; không chọn nút tạo hoặc sửa.
3. **Đọc CIDR của VPC.** Ghi chú IPv4 CIDR block, trạng thái VPC, tenancy nếu hiển thị và các CIDR bổ sung nếu có. Xác định network address và prefix length. Không chép thông tin account hoặc topology nội bộ vào nơi công khai.
4. **Mở danh sách Subnets.** Lọc subnet theo VPC vừa chọn. Với từng subnet được phép xem, ghi nhận subnet CIDR, Availability Zone, trạng thái và cấu hình auto-assign public IPv4 nếu giao diện hiển thị.
5. **So sánh subnet CIDR.** Kiểm tra bằng mắt hoặc công cụ tính CIDR cục bộ xem mỗi subnet có nằm trong VPC CIDR hay không và có chồng lấn với subnet khác trong cùng VPC không. Không thay đổi địa chỉ.
6. **Quan sát Route tables.** Mở route table liên kết với một subnet và đọc các destination cùng target. Xác định local route và xem có route đến Internet Gateway, NAT Gateway hay target khác hay không. Chỉ từ route table, không kết luận mọi traffic đều được phép; cần xét security group, network ACL, địa chỉ public và các lớp khác.
7. **Liên hệ subnet với topology.** Ghi lại subnet nằm ở AZ nào và thử phân loại public/private theo đường định tuyến, không dựa vào tên subnet. Nếu không đủ thông tin hoặc không có quyền xem route table, ghi rõ giới hạn đó.

Sau khi quan sát, hãy trả lời:

- VPC CIDR là gì và có prefix length nào?
- Một subnet cụ thể nằm trong AZ nào và CIDR của nó là gì?
- Subnet đó có route liên quan đến Internet Gateway hoặc NAT Gateway không?
- Bạn có đủ bằng chứng để gọi subnet là public hoặc private không? Những thông tin nào cần kiểm tra thêm?

Không bấm **Create VPC**, **Edit CIDRs**, **Edit subnet settings**, **Delete**, hoặc sửa route table. Nếu không có quyền xem, hoàn thành phần phân tích bằng sơ đồ ví dụ ở bài này.

## 6. Thực hành

> **Mục tiêu:** Lập bản quy hoạch IPv4 cho dev và prod với CIDR VPC không chồng lấn, chia subnet cho hai AZ và ba tầng mạng, đồng thời giải thích cách kiểm tra phạm vi và chỗ dự trữ.  
> **Môi trường:** Thiết kế cục bộ cho dự án học tập; không triển khai VPC hoặc subnet lên AWS trong bài này.  
> **Chi phí dự kiến:** Không phát sinh chi phí AWS vì không tạo tài nguyên. Các tài nguyên mạng triển khai ở bài lab sau, đặc biệt NAT Gateway và luồng dữ liệu, có thể phát sinh phí.  
> **Rủi ro và phạm vi:** `10.20.0.0/16` và `10.30.0.0/16` chỉ là dải minh họa. Không đưa chúng vào hệ thống thật trước khi đối chiếu với mạng hiện hữu, VPN, VPC khác và kế hoạch kết nối. Không sửa cấu hình mạng trong AWS account.

### Kiến trúc lab

Thiết kế minh họa gồm hai VPC không chồng lấn: một cho dev và một cho prod. Mỗi VPC dự trữ các subnet public, application-private và data-private ở hai AZ. Tất cả địa chỉ trong bảng dùng private IPv4 space; đường đi ra ngoài Internet sẽ được quyết định sau bằng route table và các thành phần như Internet Gateway/NAT Gateway, không phải chỉ bởi CIDR.

```text
Dev VPC: 10.20.0.0/16                  Prod VPC: 10.30.0.0/16
├── AZ-a                                ├── AZ-a
│   ├── Public: 10.20.0.0/24           │   ├── Public: 10.30.0.0/24
│   ├── App:    10.20.10.0/24          │   ├── App:    10.30.10.0/24
│   └── Data:   10.20.20.0/24          │   └── Data:   10.30.20.0/24
└── AZ-b                                └── AZ-b
    ├── Public: 10.20.1.0/24                ├── Public: 10.30.1.0/24
    ├── App:    10.20.11.0/24               ├── App:    10.30.11.0/24
    └── Data:   10.20.21.0/24               └── Data:   10.30.21.0/24
```

Các CIDR này chỉ là mẫu để luyện thiết kế. Tài nguyên thực tế, số AZ, kích thước subnet và khả năng kết nối cần được xác minh trước khi triển khai. Không tạo một VPC mới chỉ để giống sơ đồ nếu lab dùng chung trong `dev/lab/` hoặc `prod/lab/` đã được khởi tạo.

### Điều kiện trước khi bắt đầu

- Đọc các khái niệm CIDR, VPC, subnet, AZ và route table trong phần lý thuyết.
- Có giấy/bảng tính hoặc trình soạn thảo để lập bảng; không cần AWS CLI, Terraform, access key hoặc công cụ cài đặt riêng.
- Nếu chọn đối chiếu AWS Console, cần account và quyền chỉ đọc phù hợp. Xác nhận account/Region trước khi mở tài nguyên.
- Trước khi chọn CIDR dùng thật, cần có danh sách các mạng hiện hữu cần kết nối. Nếu chưa có danh sách đó, coi mọi dải trong bài chỉ là ví dụ.

### Các bước thực hiện

1. **Lập danh sách mạng cần tránh.** Ghi các dải đang dùng trong văn phòng, on-premises, VPN, VPC AWS khác và các mạng dự kiến kết nối. Nếu không biết dải nào đang dùng, đánh dấu là “chưa xác minh” thay vì giả định không có xung đột.
2. **Chọn CIDR minh họa cho VPC.** Dùng `10.20.0.0/16` cho dev và `10.30.0.0/16` cho prod trong bài tập. Kiểm tra hai dải có chồng lấn với nhau không. Ghi rõ rằng trước khi dùng thật, phải kiểm tra xung đột với inventory mạng của tổ chức.
3. **Tính số địa chỉ.** Với mỗi VPC `/16`, tính số bit host là `32 - 16 = 16` và tổng địa chỉ là `2^16 = 65,536`. Không hiểu số này là số địa chỉ có thể gán trong một subnet; đây là quy mô của toàn CIDR VPC.
4. **Tạo bảng subnet cho dev.** Dùng bảng kiến trúc ở trên để ghi tên subnet, tầng mạng, AZ, CIDR, prefix length và mục đích. Xác nhận từng subnet nằm trong `10.20.0.0/16`.
5. **Tạo bảng subnet cho prod.** Lặp lại thiết kế với `10.30.0.0/16`, giữ cấu trúc tương đương để dễ so sánh nhưng đảm bảo không dùng lại CIDR dev.
6. **Kiểm tra subnet overlap.** So sánh từng cặp subnet trong một VPC. Các subnet có thể nằm trong cùng VPC nhưng không được chồng lấn. Kiểm tra thêm rằng subnet CIDR được căn đúng theo prefix và nằm hoàn toàn bên trong CIDR VPC.
7. **Kiểm tra công suất.** Với subnet `/24`, tính `2^(32-24) = 256` địa chỉ tổng cộng. Trừ 5 địa chỉ AWS giữ lại, còn 251 theo quy tắc subnet IPv4 thông thường. Ghi chú rằng dịch vụ cụ thể có thể cần địa chỉ dự trữ hoặc có yêu cầu kích thước riêng.
8. **Đánh dấu khoảng địa chỉ dự trữ.** Trong mỗi VPC `/16`, xác định các khoảng chưa cấp cho subnet để dành cho tăng trưởng, thêm AZ, thêm subnet hoặc dịch vụ mới. Ghi lại quy tắc đặt tên và cấp block để người khác có thể mở rộng mà không vô tình tạo overlap.
9. **Xác định route table ở mức thiết kế.** Đánh dấu subnet nào dự kiến là public, application-private hoặc data-private. Chưa gọi chúng là public/private chỉ từ tên; ghi rõ route cần thiết để đạt vai trò đó. Cấu hình route chi tiết sẽ học ở các bài Internet Gateway và NAT Gateway.
10. **Ghi kết quả cho lab dùng chung.** Lưu bản thiết kế và quyết định CIDR trong ghi chú dự án. Khi lab tích hợp được triển khai, cấu hình mạng sẽ thuộc root module dùng chung của `dev/lab/` và `prod/lab/`; không tạo state Terraform riêng cho Bài 2. Bài này chưa yêu cầu tạo hoặc sửa file Terraform.

### Xác minh kết quả

Thiết kế đạt yêu cầu khi:

- CIDR VPC dev và prod khác nhau và không chồng lấn.
- Mọi subnet CIDR nằm hoàn toàn trong VPC CIDR tương ứng.
- Không có hai subnet nào trong cùng một VPC bị chồng lấn.
- Mỗi subnet được gán đúng một AZ trong Region dự kiến; các AZ-a/AZ-b chỉ là tên minh họa, khi triển khai phải chọn AZ khả dụng thực tế.
- Mỗi subnet có mục đích rõ ràng (public, application-private hoặc data-private) và vai trò public/private sẽ được xác định bằng route/configuration, không chỉ bằng tên.
- Có phép tính dung lượng IPv4 và ghi chú về 5 địa chỉ AWS giữ lại.
- Có ghi nhận kiểm tra overlap với mạng on-premises, VPN, VPC khác và các mạng dự kiến kết nối; mọi dải chưa được xác minh được đánh dấu rõ.
- Có dự trữ khoảng địa chỉ để mở rộng thay vì dùng hết CIDR ngay từ đầu.

### Xử lý lỗi thường gặp

| Triệu chứng hoặc lỗi thiết kế | Nguyên nhân có thể có | Cách kiểm tra và khắc phục |
|---|---|---|
| Subnet CIDR nằm một phần ngoài VPC CIDR | Chọn network address hoặc prefix không phù hợp | Tính ranh giới của VPC và subnet; bảo đảm toàn bộ subnet range nằm trong VPC |
| Hai subnet không thể cùng tạo trong một VPC | CIDR subnet chồng lấn | Liệt kê start/end address của từng subnet hoặc dùng công cụ CIDR đáng tin cậy để kiểm tra overlap; cấp lại dải không trùng |
| Dev và prod không thể định tuyến như dự kiến khi kết nối | Hai môi trường hoặc mạng kết nối dùng dải chồng lấn | Kiểm tra toàn bộ CIDR ở các phía trước khi thiết kế VPN, peering hoặc Transit Gateway; cần xử lý overlap có kế hoạch, không chỉ thêm route |
| Subnet thiếu IP khi workload scale | CIDR quá nhỏ hoặc dịch vụ tiêu thụ nhiều địa chỉ hơn dự kiến | Kiểm tra số địa chỉ còn lại, yêu cầu cụ thể của dịch vụ và tốc độ tăng trưởng; thiết kế subnet đủ lớn trước khi triển khai |
| Gọi subnet là public chỉ vì nó dùng dải `10.x.x.x` | Nhầm private IPv4 address với loại subnet | Kiểm tra route table, Internet Gateway, public addressing và các rule bảo mật liên quan |
| Sơ đồ có hai AZ nhưng ứng dụng vẫn không chịu lỗi AZ | Chỉ tạo subnet mà chưa phân phối workload hoặc dữ liệu | Kiểm tra cấu hình service, load balancer, desired capacity, data replication và failover; subnet đa AZ chỉ là một phần nền tảng |
| Chọn AZ-a/AZ-b theo đúng tên trong sơ đồ nhưng không có sẵn | Tên AZ trong ví dụ không phải cam kết về tên AZ hoặc mapping cho mọi account | Khi triển khai, truy vấn AZ khả dụng trong Region và dùng AZ ID nếu cần định danh vị trí nhất quán giữa nhiều account |

### Dọn dẹp tài nguyên

Không có tài nguyên AWS nào được tạo trong bài này. Không chạy `terraform apply` hoặc `terraform destroy`, không tạo VPC/subnet trên Console và không xóa mạng đang tồn tại. Chỉ cần lưu bản thiết kế CIDR cục bộ nếu muốn tiếp tục dùng cho các bài networking tiếp theo.

## 7. Bài tập tự kiểm tra

Trả lời bằng lập luận, phép tính hoặc sơ đồ. Nếu một giả định chưa thể xác minh, hãy nêu giả định đó thay vì đưa ra kết luận chắc chắn.

1. Dải `10.20.0.0/16` có bao nhiêu bit dành cho host và tổng cộng bao nhiêu địa chỉ IPv4? Vì sao không thể dùng toàn bộ số đó làm địa chỉ cho một subnet?
2. Hai subnet `10.20.1.0/24` và `10.20.2.0/24` có chồng lấn không? Giải thích cách bạn xác định. Một subnet `10.20.1.128/25` sẽ có quan hệ gì với `10.20.1.0/24`?
3. Vì sao nên kiểm tra CIDR của mạng văn phòng và on-premises trước khi tạo VPC, dù VPC mới có thể hoạt động độc lập ngay hôm nay?
4. Một subnet có CIDR `10.20.10.0/24`. Bao nhiêu địa chỉ IPv4 tổng cộng thuộc dải, và còn bao nhiêu địa chỉ theo quy tắc 5 địa chỉ AWS giữ lại? Vì sao số địa chỉ khả dụng cho workload vẫn có thể thấp hơn?
5. Một subnet tên `public-app` có private IPv4 CIDR. Chỉ dựa vào tên và CIDR đó, có thể kết luận subnet truy cập được từ Internet không? Nêu thêm những cấu hình cần kiểm tra.
6. Thiết kế một VPC có subnet ở hai AZ và ba tầng public, application-private, data-private. Nêu CIDR ví dụ, cách bảo đảm không overlap, và cách để dành dải cho tăng trưởng.
7. Vì sao `dev/lab/` và `prod/lab/` nên dùng CIDR riêng, dù các resource hiện tại chưa kết nối với nhau? Nêu ít nhất hai tình huống trong tương lai mà overlap có thể trở thành vấn đề.

### Gợi ý đáp án

1. `/16` cố định 16 bit network nên còn `32 - 16 = 16` bit host. Tổng số địa chỉ là `2^16 = 65,536`. Trong AWS, CIDR VPC được chia thành các subnet nhỏ hơn; mỗi subnet có ranh giới CIDR riêng, AWS giữ lại 5 IPv4 address trong mỗi subnet, và một dịch vụ có thể cần thêm dung lượng riêng.
2. Hai `/24` bắt đầu ở các khối 256 địa chỉ liên tiếp: `10.20.1.0` đến `10.20.1.255` và `10.20.2.0` đến `10.20.2.255`, nên không chồng lấn. `10.20.1.128/25` nằm hoàn toàn trong `10.20.1.0/24`, nên bị overlap với subnet `/24` đó và không thể cùng làm các subnet độc lập trong một VPC.
3. VPC có thể cần kết nối về sau qua VPN, VPC peering hoặc Transit Gateway. Nếu CIDR hai phía chồng lấn, route không thể phân biệt địa chỉ đích thuộc mạng nào theo cách thông thường. Điều này có thể buộc phải đổi CIDR hoặc dùng giải pháp chuyển đổi địa chỉ phức tạp.
4. `/24` có `2^(32-24) = 256` địa chỉ. Sau khi AWS giữ lại 5 địa chỉ, còn 251 theo quy tắc cơ bản. Interface, dịch vụ AWS và yêu cầu dự trữ cho scale có thể làm số địa chỉ còn thực tế thấp hơn.
5. Không. `public-app` chỉ là tên và private IPv4 là loại địa chỉ; cần kiểm tra route table có route đến Internet Gateway hay không, tài nguyên có public IPv4/public address phù hợp không, cùng security group, network ACL và cấu hình của dịch vụ.
6. Một thiết kế minh họa là dùng `10.20.0.0/16` cho dev hoặc `10.30.0.0/16` cho prod, sau đó gán `/24` khác nhau cho mỗi tổ hợp tầng/AZ. Ví dụ dev có public `10.20.0.0/24` và `.1.0/24`, app `10.20.10.0/24` và `.11.0/24`, data `10.20.20.0/24` và `.21.0/24`. Cần kiểm tra mọi block không overlap, còn trong VPC `/16`, và giữ một phần dải chưa cấp để mở rộng.
7. Tách CIDR ngay từ đầu giúp kết nối và quản lý route về sau. Ví dụ hai VPC cần nối qua peering/Transit Gateway; hoặc dev/prod cần kết nối VPN tới cùng mạng on-premises. Nếu địa chỉ chồng lấn, các route không thể định tuyến chính xác theo thiết kế thông thường.

## Tổng kết kiến thức và nguyên tắc áp dụng

CIDR là cách mô tả một khối địa chỉ IPv4 bằng network address và prefix length. Prefix nhỏ hơn biểu thị dải lớn hơn; prefix lớn hơn biểu thị dải nhỏ hơn. Khi lập subnet trong AWS, phải kiểm tra subnet nằm hoàn toàn trong VPC CIDR, không chồng lấn với subnet khác và có đủ địa chỉ sau khi trừ các địa chỉ AWS giữ lại cùng nhu cầu riêng của dịch vụ.

VPC, subnet và AZ có phạm vi khác nhau: VPC thuộc một Region; subnet là phân đoạn CIDR nằm trong đúng một AZ; route table quyết định đường đi; security group và network ACL kiểm soát traffic được phép. Public/private là đặc tính định tuyến và cấu hình, không phải kết quả của tên subnet hoặc loại private IP.

Trước khi chọn CIDR cho dev, prod hay lab, hãy kiểm kê các mạng hiện có và mạng có thể cần kết nối trong tương lai. Dải trong bài chỉ là ví dụ, không được dùng thật nếu chưa xác minh không overlap. Bài thực hành này chỉ tạo bản thiết kế cục bộ; các bài Internet Gateway, NAT Gateway và lab tích hợp sau sẽ dùng kiến thức này để triển khai networking vào root module xuyên suốt `dev/lab/` và `prod/lab/`.

Áp dụng kiến thức vào một môi trường mới bằng cách hỏi: “Những mạng nào cần liên lạc với nhau?”, “Có CIDR nào đang được dùng ở các phía đó?”, “Mỗi tầng và AZ cần bao nhiêu địa chỉ?”, và “Còn đủ không gian để mở rộng mà không phải đánh lại địa chỉ không?”
