# Section 1 — Bài 5: Kiểm soát luồng truy cập bằng security groups và network ACLs

## Mục tiêu bài học

Sau bài này, người học có thể:

- Phân biệt vai trò của route table, security group và network access control list (network ACL) trong đường đi của một packet.
- Giải thích security group là stateful, áp dụng ở network interface và chỉ có rule Allow; giải thích network ACL là stateless, áp dụng ở subnet, xử lý rule theo thứ tự và có thể Allow hoặc Deny.
- Đọc rule inbound/outbound để xác định source, destination, protocol, port range và thứ tự đánh giá.
- Tính được vì sao response traffic cần rule phù hợp trong network ACL, kể cả ephemeral ports, nhưng thường không cần rule phản hồi riêng trong security group stateful.
- Thiết kế rule theo least privilege bằng cách tham chiếu security group của thành phần nguồn thay vì mở CIDR rộng không cần thiết.
- Đánh giá tác động của default security group/default network ACL, nhận diện các cấu hình thường mở quá rộng và kiểm thử cả trường hợp được phép lẫn bị từ chối.
- Mở rộng networking module trong `dev/lab/` bằng các security group có mục đích rõ ràng, đọc Terraform plan trước khi triển khai và tránh thay đổi đột ngột network ACL đang được dùng chung.

## 1. Bối cảnh và vấn đề

Định tuyến trả lời câu hỏi “packet sẽ được gửi đến đâu?”, nhưng không quyết định một mình rằng packet có được workload chấp nhận hay không. Một route có thể đưa traffic đến đúng subnet mà firewall vẫn chặn; ngược lại, firewall có thể cho phép traffic nhưng không có route khả dụng để chuyển packet đến đích.

Trong Amazon VPC, hai lớp kiểm soát mạng phổ biến là **security group** và **network access control list (network ACL)**. Chúng giải quyết các phạm vi khác nhau:

- Security group kiểm soát traffic ở network interface của tài nguyên hoặc workload.
- Network ACL kiểm soát traffic ở ranh giới subnet.
- Route table chọn next hop cho packet dựa trên địa chỉ đích.

Ví dụ, một ứng dụng nhiều tầng có public Application Load Balancer (ALB), application tasks trong private subnet và database trong subnet riêng. Ta có thể cho phép:

1. Khách hàng kết nối HTTPS đến ALB.
2. Chỉ ALB được kết nối đến application tasks trên cổng ứng dụng.
3. Chỉ application tasks được kết nối đến database trên cổng database.

Nếu thay vì mô hình đó, mọi security group đều cho phép mọi cổng từ `0.0.0.0/0`, một lỗi ở một workload có thể mở rộng thành nguy cơ cho nhiều thành phần khác. Nếu network ACL được cấu hình thiếu chiều phản hồi, kết nối hợp lệ cũng có thể timeout dù inbound rule ban đầu đã cho phép.

Security group và network ACL không thay thế IAM. IAM kiểm soát hành động trên tài nguyên AWS; các cơ chế mạng kiểm soát packet đi đến network interface/subnet. Một yêu cầu chỉ thành công khi các lớp liên quan đều cho phép và ứng dụng đích đang lắng nghe.

## 2. Khái niệm và thành phần cốt lõi

### Security group

**Security group (SG)** là firewall stateful gắn với một hoặc nhiều network interface trong VPC. Nhiều dịch vụ AWS sử dụng security group thông qua network interface của chúng. Rule mô tả traffic inbound hoặc outbound được phép theo protocol, port range và địa chỉ nguồn/đích hoặc security group khác.

Các đặc tính quan trọng:

- Security group chỉ có rule **Allow**. Traffic không khớp rule được cho phép sẽ bị từ chối ngầm; không có rule Deny tường minh trong security group.
- Security group là **stateful**: khi một kết nối được cho phép, traffic phản hồi thuộc kết nối đó được theo dõi trạng thái và thường không cần rule đối xứng riêng.
- Rule inbound kiểm soát traffic đi vào network interface; rule outbound kiểm soát traffic rời network interface.
- Nếu nhiều security group gắn vào cùng một network interface, các rule Allow được kết hợp theo phép hợp. Một rule trong group này không thể dùng để phủ định rule Allow trong group khác.
- Security group tham chiếu một security group khác có thể diễn tả quan hệ giữa workload rõ hơn so với CIDR cố định, chẳng hạn “cho phép traffic từ ALB security group đến application security group”.

Security group không tạo đường định tuyến, không kiểm tra payload ở mức ứng dụng, không thay thế xác thực người dùng và không chặn được traffic bằng một explicit Deny. Khi cần ngăn traffic đã được một security group khác cho phép, phải sửa hoặc gỡ rule Allow phù hợp, thay vì tìm cách thêm Deny.

### Inbound và outbound rules

Một rule thường có các trường:

| Trường | Ý nghĩa | Ví dụ |
|---|---|---|
| Direction | Chiều packet được kiểm soát | Inbound vào workload, outbound rời workload |
| Protocol | Giao thức IP hoặc transport được cho phép | TCP, UDP, ICMP hoặc all protocols |
| Port range | Cổng đích hoặc khoảng cổng, nếu giao thức dùng port | TCP 443 cho HTTPS |
| Source/destination | CIDR hoặc security group được phép giao tiếp | `10.20.0.0/16` hoặc SG của ALB |
| Description | Ghi chú mục đích | “Cho phép ALB gọi application trên port 8080” |

Đối với TCP/UDP, port trong rule là port đích của packet theo chiều đang đánh giá. Ví dụ, inbound TCP 443 cho phép traffic đến listener HTTPS trên cổng 443; outbound TCP 443 cho phép workload khởi tạo traffic đến đích có cổng 443. Cần xác định ứng dụng thật sự lắng nghe trên cổng nào, không suy luận chỉ từ tên dịch vụ.

### Stateful và connection tracking

**Stateful** nghĩa là security group theo dõi trạng thái kết nối được cho phép. Ví dụ, nếu EC2 khởi tạo kết nối outbound TCP đến server HTTPS bên ngoài và outbound rule cho phép kết nối đó, response thuộc kết nối này có thể đi vào qua security group mà không cần một inbound rule mở rộng cho dải ephemeral ports.

Điều này không có nghĩa mọi traffic inbound đều được mở. Một kết nối mới khởi tạo từ bên ngoài vẫn phải thỏa inbound rule. Cũng không nên hiểu stateful là không cần quan tâm đến network ACL, route, host firewall hay ứng dụng; các lớp đó vẫn có thể chặn traffic.

### Network ACL

**Network ACL (NACL)** là firewall stateless gắn với subnet. Một network ACL có thể được liên kết với một hoặc nhiều subnet trong cùng VPC; mỗi subnet tại một thời điểm được liên kết với một network ACL. Nếu không chỉ định association riêng, subnet dùng main/default network ACL.

Các đặc tính chính:

- NACL hỗ trợ rule **Allow** và **Deny**.
- Rule được đánh số; AWS xét từ số nhỏ đến lớn và áp dụng rule đầu tiên khớp traffic.
- Nếu không có rule nào khớp, traffic bị từ chối ngầm.
- NACL là **stateless**: chiều đi và chiều về được đánh giá độc lập. Phải cho phép cả hai chiều của kết nối.
- NACL được đánh giá ở ranh giới subnet, do đó có thể ảnh hưởng nhiều network interface trong subnet cùng lúc.
- Các rule IPv4 và IPv6 phải được xem xét riêng; một rule cho IPv4 không tự áp dụng cho IPv6.

Quy tắc đầu tiên khớp có ý nghĩa lớn. Ví dụ, nếu rule số `90` deny toàn bộ TCP từ một CIDR và rule số `100` allow TCP 443 từ chính CIDR đó, traffic bị rule `90` chặn trước, nên rule `100` không được xét. Rule số lớn hơn không ghi đè rule số nhỏ hơn.

### Ephemeral ports và traffic phản hồi

Khi client khởi tạo kết nối TCP, nó thường chọn một **ephemeral port** — cổng tạm thời phía client — làm source port. Server trả response đến source port đó. Dải ephemeral port cụ thể có thể tùy hệ điều hành/client và loại kết nối; không nên giả định một con số duy nhất cho mọi workload.

Vì NACL stateless, cần cho phép packet phản hồi theo chiều ngược lại. Ví dụ:

```text
Client private subnet → server TCP 443
  source port: ephemeral
  destination port: 443

Server → client private subnet
  source port: 443
  destination port: ephemeral port của client
```

Nếu NACL outbound chỉ cho phép cổng đích 443 nhưng NACL inbound không cho phép response đến dải ephemeral port phù hợp, kết nối có thể bắt đầu nhưng response bị chặn. Security group stateful theo dõi kết nối nên thông thường không cần mở inbound ephemeral ports chỉ để nhận response của outbound connection đã được cho phép.

Không nên mở toàn bộ ephemeral range từ mọi nguồn nếu có thể thu hẹp theo CIDR và luồng thực tế. Hãy xác định client/server nằm ở đâu, hướng packet và loại kết nối, rồi kiểm tra tài liệu dịch vụ cùng cấu hình hệ điều hành.

### Default security group và default network ACL

Hai loại “default” không đồng nghĩa với chính sách từ chối mọi traffic:

- **Default security group của VPC:** thường có inbound rule cho phép các network interface gắn cùng security group giao tiếp với nhau và outbound rule cho phép mọi traffic. Vì vậy, gắn default SG vào workload mà không xem rule có thể tạo kết nối ngang giữa các thành viên của group và egress rộng.
- **Security group mới tạo:** nếu không cấu hình outbound rule khác, mặc định AWS tạo rule outbound cho phép mọi traffic. Khi cần egress giới hạn, phải chủ động thay đổi chính sách outbound.
- **Default network ACL:** mặc định thường cho phép mọi inbound và outbound traffic. NACL tùy chỉnh mới tạo thường không có rule allow sẵn để cho phép traffic, nên traffic bị từ chối cho đến khi thêm rule phù hợp.

Luôn đọc rule hiện tại trong account thay vì dựa vào giả định về default, bởi default ACL có thể đã được chỉnh sửa. Trong production, không nên dựa vào default group/ACL như một thiết kế bảo mật có chủ đích.

### So sánh security group, network ACL và route table

| Cơ chế | Phạm vi | Cách đánh giá | Allow/Deny | Theo dõi trạng thái kết nối? | Câu hỏi chính |
|---|---|---|---|---|---|
| Route table | Subnet | Chọn route/target phù hợp nhất theo destination | Không phải firewall Allow/Deny | Không | Packet đi theo đường nào? |
| Security group | Network interface/tài nguyên | Tập hợp rule Allow; traffic không khớp bị deny ngầm | Allow | Có, stateful | Traffic nào được đến/rời workload? |
| Network ACL | Subnet | Rule số thấp nhất khớp được áp dụng trước | Allow và Deny | Không, stateless | Traffic nào được qua ranh giới subnet theo từng chiều? |

## 3. Cách hoạt động: kiểm tra một kết nối

Xét luồng HTTPS từ Internet đến một ứng dụng sau ALB:

```text
Client
  │ TCP 443
  ▼
Route đến public ALB
  │ NACL ingress/egress của public subnet
  │ Security group của ALB
  ▼
ALB
  │ TCP 8080, nguồn là ALB security group
  ▼
Application trong private subnet
  │ NACL ingress/egress của private subnet
  │ Security group của application
  ▼
Database nếu ứng dụng cần truy cập
```

Để kết nối thành công, các điều kiện phải được đánh giá theo từng chặng:

1. **Đường đi phải tồn tại.** Route table của subnet và các thành phần định tuyến phải đưa packet đến đúng network interface. SG/NACL không tạo route.
2. **NACL của subnet phải cho phép packet.** AWS xét ingress hoặc egress direction tương ứng, từ rule số thấp lên cao. NACL phải cho phép cả packet request và response ở hai phía subnet.
3. **SG gắn với network interface phải cho phép traffic mới đến workload.** Với request HTTPS, SG của ALB cần inbound rule TCP 443 từ các nguồn được phép.
4. **Mỗi chặng nội bộ được kiểm soát riêng.** ALB mở kết nối mới đến application. SG application nên cho phép cổng ứng dụng chỉ từ SG của ALB, không phải từ toàn bộ Internet.
5. **Database chỉ nhận từ tầng ứng dụng.** SG database cho phép đúng cổng database và chỉ từ SG của application. Không mở port database ra public CIDR.
6. **Response được đánh giá theo trạng thái và lớp firewall.** SG stateful cho phép response thuộc các kết nối hợp lệ; NACL stateless cần rule chiều ngược lại phù hợp.
7. **Ứng dụng vẫn phải sẵn sàng.** Listener, health check, TLS, host firewall và ứng dụng có thể làm request thất bại dù route/SG/NACL đã cho phép.

Nếu một rule không cho phép request, security group deny ngầm hoặc NACL chuyển sang rule khớp tiếp theo; nếu không có rule khớp, NACL deny ngầm. Nếu route thiếu, packet không có next hop hữu ích. Trong vận hành, một kết nối timeout không tự chỉ ra lớp nào lỗi; cần kiểm tra route, SG, NACL, địa chỉ, listener, DNS và logs/metrics theo thứ tự.

### Mô hình rule cho ứng dụng nhiều tầng

| Security group | Inbound cần thiết | Outbound cần thiết | Mục tiêu |
|---|---|---|---|
| ALB SG | TCP 443 từ client CIDR phù hợp; website công khai có thể cần `0.0.0.0/0` và/hoặc IPv6 tương ứng | TCP 8080 đến application SG | Nhận HTTPS và chuyển tiếp đến app |
| Application SG | TCP 8080 từ ALB SG | TCP 3306 đến database SG; egress bổ sung chỉ khi workload cần | Chỉ nhận từ ALB; gọi database |
| Database SG | TCP 3306 từ application SG | Chỉ các luồng cần thiết theo kiến trúc | Không nhận trực tiếp từ Internet hoặc ALB |

Các cổng `8080` và `3306` chỉ là ví dụ. Hãy thay bằng port thực của ứng dụng/database. ALB health checks cũng phải dùng port/protocol mà application thực sự cung cấp. Nhiều giải pháp cần thêm luồng DNS, logging, package updates, telemetry hoặc AWS API; các luồng đó cần được xác định riêng thay vì mở all egress một cách vô điều kiện.

## 4. Tư duy kiến trúc, bảo mật, chi phí và đánh đổi

### Tính sẵn sàng và khả năng phục hồi

Security group và NACL là cấu hình mạng, không phải cơ chế nhân bản workload. Một rule quá hẹp có thể làm health check thất bại trên mọi AZ; một NACL dùng chung cho nhiều subnet có thể tạo lỗi diện rộng. Hãy triển khai thay đổi mạng có kiểm soát và xác minh trên từng subnet/AZ.

Security group được gắn với network interface; khi workload thay đổi, rule tham chiếu security group có thể theo dõi thành viên của group thay vì phải cập nhật thủ công từng private IP. Điều này hữu ích cho workload có địa chỉ thay đổi, nhưng cũng có nghĩa membership của group phải được quản trị chặt.

Network ACL có phạm vi subnet và stateless. Một thay đổi NACL có thể tác động đồng loạt đến nhiều resource trong subnet và cần cả rule request/response. Vì vậy, NACL thường phù hợp cho lớp lọc subnet tương đối thô hoặc yêu cầu cụ thể; tránh sử dụng nó làm công cụ duy nhất cho policy phức tạp theo workload.

Không thay NACL đang gắn với subnet dùng chung nếu chưa có inventory, plan, thử nghiệm và phương án rollback. Tránh gỡ route, SG hoặc NACL để “mô phỏng lỗi” trên một mạng được dùng bởi các bài sau.

### Bảo mật

- Áp dụng least privilege: chỉ mở protocol, port, hướng và nguồn/đích cần thiết.
- Ưu tiên tham chiếu SG của tầng gọi thay cho CIDR rộng khi traffic giữa workload trong VPC; ví dụ application SG nhận traffic từ ALB SG.
- Dùng `0.0.0.0/0` hoặc `::/0` chỉ khi dịch vụ thật sự công khai và có kiểm soát phù hợp. Với website public, thường mở listener 443; không vì thế mà mở cổng quản trị hoặc database.
- Tránh mở SSH/RDP từ mọi địa chỉ Internet. Dùng phương án quản trị an toàn phù hợp như AWS Systems Manager Session Manager hoặc cơ chế đã được tổ chức phê duyệt.
- Security group không có Deny. Khi review nhiều SG gắn trên cùng network interface, tính hợp của mọi rule Allow; đừng giả định một SG khác sẽ chặn rule rộng.
- Xem rule inbound và outbound. SG mới thường có all-egress mặc định nếu không thay đổi; hạn chế outbound cần được thiết kế có chủ đích và kiểm thử để không phá DNS, telemetry, updates hoặc AWS API cần thiết.
- NACL cho phép Deny nhưng stateless, nên phải review thứ tự rule và chiều phản hồi. Sai rule có thể chặn cả nhiều workload trong subnet.
- Lưu mô tả rõ ràng cho rule, quản lý bằng IaC, review diff/plan và tránh thao tác thủ công tạo drift.
- Security group/NACL không mã hóa packet và không xác thực người dùng; dùng TLS, IAM, xác thực ứng dụng và logging theo yêu cầu.

### Chi phí

Security group và network ACL thường không có phí riêng cho từng rule, nhưng kiểm tra bảng giá hiện hành và giới hạn dịch vụ theo Region. Chi phí thực tế thường đến từ tài nguyên dùng để kiểm thử hoặc những dịch vụ mạng khác trong kiến trúc, chẳng hạn EC2, ALB, NAT Gateway, public IPv4, data transfer và logging.

Tăng số lượng rule hoặc group chủ yếu làm tăng độ phức tạp quản trị và có thể chạm quota, không nên nhầm nó với chi phí của compute/network processing. Vượt quota có thể ngăn triển khai hoặc scale; cần xem giới hạn hiện hành của VPC/security group/NACL.

Trong bài thực hành này không cần khởi chạy compute hoặc tạo traffic Internet để hiểu rule. Kiểm tra Terraform plan và quan sát cấu hình có thể đủ; chỉ chạy data-plane test khi đã xác nhận tài nguyên, lưu lượng, chi phí và phạm vi.

### Lựa chọn kiến trúc và đánh đổi

- **Security group làm lớp kiểm soát chính cho workload:** Phù hợp vì SG gắn theo network interface, stateful và hỗ trợ tham chiếu SG. Cần nhớ rule chỉ Allow và nhiều SG được hợp nhất.
- **NACL làm lớp kiểm soát subnet:** Hữu ích cho guardrail subnet hoặc yêu cầu explicit Deny, nhưng tăng độ phức tạp vì rule có thứ tự và stateless. Một rule sai có blast radius lớn hơn một SG riêng của workload.
- **Dùng CIDR trong SG:** Phù hợp với client bên ngoài hoặc dải mạng cố định. Dải quá rộng làm mất tính least privilege; IP thay đổi có thể khiến rule nhanh lỗi thời.
- **Dùng SG reference:** Phù hợp với quan hệ giữa các thành phần AWS trong phạm vi tương thích. Rule thể hiện “chỉ workload có SG nguồn này” thay vì phụ thuộc IP động. Cần quản lý chính xác SG nào được phép gắn và hiểu giới hạn của reference theo topology/connection.
- **Chỉ dựa vào NACL để bảo mật:** Không đủ vì NACL chỉ là một lớp subnet, không thay IAM, SG, host firewall hoặc kiểm soát ứng dụng.
- **Chỉ dựa vào SG:** Có thể phù hợp với nhiều VPC workload do tính stateful và theo network interface; nếu tổ chức cần explicit subnet-level deny/guardrail thì cần đánh giá thêm NACL hoặc firewall dịch vụ chuyên dụng.

### Giới hạn và lưu ý khác

- SG và NACL không phải bộ lọc theo domain name, URL path hay nội dung HTTP. Nếu yêu cầu cần lọc tầng ứng dụng, dùng proxy, web application firewall hoặc giải pháp phù hợp.
- NACL không thay thế các route. NACL cho phép packet nhưng route thiếu vẫn khiến packet không đến đích.
- SG source reference không có nghĩa “mọi traffic hợp lệ từ ứng dụng”; nó cho phép traffic từ network interface được gắn SG đó theo rule/port/protocol. Ứng dụng vẫn cần xác thực và phân quyền.
- Một kết nối có thể đi qua nhiều subnet và network interface; mọi SG/NACL tương ứng trên đường đi cần được đánh giá.

## 5. Quan sát trên AWS Management Console

Phần này chỉ quan sát cấu hình. Không sửa rule hoặc association trực tiếp trong Console nếu Terraform quản lý resource đó.

1. **Xác nhận account và Region.** Mở AWS Management Console, xác nhận đúng account/Region của VPC lab. Security group và NACL cần được xem trong đúng VPC/Region.
2. **Mở Security Groups.** Trong dịch vụ VPC, chọn **Security groups** và lọc theo VPC ID. Chọn một SG của workload nếu có; nếu chưa có, xem default SG nhưng không gắn nó vào resource.
3. **Đọc inbound/outbound rules.** Ghi protocol, port range, source/destination, SG reference và description. Xác định rule nào rộng, rule nào giới hạn theo workload, và SG đó có all-egress hay không.
4. **Kiểm tra network interface association.** Nếu được phép xem, xác định resource/network interface nào đang gắn SG. Một group có rule “an toàn” vẫn có thể mở rộng quyền truy cập nếu được gắn vào nhiều workload hơn dự kiến.
5. **Mở Network ACLs.** Chọn NACL của VPC và xem inbound/outbound rule theo số thứ tự, action, protocol, port range, CIDR và subnet association. Xác định NACL có phải default hay custom, và subnet nào chịu ảnh hưởng.
6. **Lần theo một kết nối.** Chọn một luồng, ví dụ client → ALB TCP 443 → app TCP 8080 → database TCP 3306. Kiểm tra SG/NACL theo từng chặng và chiều response; ghi lại rule đầu tiên khớp ở mỗi NACL.
7. **Giữ trạng thái chỉ đọc.** Không bấm Edit, Add rule, Delete, Change association hoặc thay default NACL. Những thay đổi này có thể làm lộ dịch vụ hoặc ngắt traffic của nhiều subnet.

Nếu account không có tài nguyên hoặc quyền xem association, dùng bảng ví dụ và Terraform configuration trong bài để phân tích. Không cần tạo EC2, ALB hoặc database để hoàn thành phần Console.

## 6. Thực hành

> - **Mục tiêu:** Thiết kế và khai báo các security group theo luồng ALB → application → database trong networking module dùng chung, đồng thời đọc/đánh giá network ACL hiện có mà không thay đổi association đang phục vụ subnet.
> - **Môi trường:** Chỉ làm việc với `dev/lab/`, lab xuyên Sections 1–5. Bài này không triển khai prod và không tạo root module/state mới.
> - **Chi phí dự kiến:** Bản thân việc khai báo SG/NACL thường không tạo phí theo từng rule; compute, ALB, NAT, public IPv4, traffic và logging phục vụ kiểm thử có thể tính phí. Bài không yêu cầu tạo workload.
> - **Rủi ro và phạm vi:** Rule SG có thể mở truy cập ngay khi SG được gắn vào ENI; thay đổi NACL association có thể ảnh hưởng toàn subnet. Không gắn default SG tùy tiện, không thay default NACL, không đổi association đang tồn tại và không chạy `terraform destroy` trên root dùng chung.

### Kiến trúc bài tập

Tạo các security group mô tả quan hệ giao tiếp cho hệ thống nhiều tầng. Nếu ALB/app/database chưa được triển khai, các SG có thể được khai báo để mô hình hóa policy và được module compute/database sử dụng ở các section sau; việc tạo SG riêng chưa chứng minh data-plane connectivity.

```text
Internet/client
      │ TCP 443 (chỉ trên ALB SG)
      ▼
ALB SG
      │ TCP 8080 (source/destination SG reference)
      ▼
Application SG
      │ TCP 3306 (source/destination SG reference)
      ▼
Database SG

Network ACL: đánh giá ở subnet boundary,
             stateless, request và response đều cần rule.
```

Bài này cấu hình SG làm kiểm soát theo workload. NACL được kiểm tra ở chế độ đọc và phân tích rule trên giấy; không thay NACL association trên private/public subnet dùng chung. Lý do là NACL stateless và tác động theo subnet, nên một thay đổi chưa kiểm thử có thể làm hỏng traffic của các section khác.

### Điều kiện trước khi bắt đầu

- Đã đọc bài 2 về CIDR/VPC và bài 3–4 về IGW/NAT/route; hiểu route và firewall là hai lớp khác nhau.
- Xác định root module, state/backend, VPC ID và module networking hiện có trong `dev/lab/`.
- Nếu VPC chưa tồn tại trong state, đây là bài thiết kế và plan; không tự tạo một mạng trùng hoặc chọn CIDR tùy ý.
- Xác định port/protocol thật cần dùng. Ví dụ dưới đây sử dụng HTTPS 443, app 8080, MySQL 3306 để minh họa, không phải mặc định cho mọi hệ thống.
- Chỉ có CIDR client được phê duyệt nếu cần mở ALB công khai. Không thay bằng `0.0.0.0/0` cho SSH/RDP hoặc database.
- Terraform provider/version đã được khai báo ở root. Có file vars mẫu không chứa credentials; không commit `terraform.tfvars`.
- Có quyền đọc/plan cần thiết; quyền apply chỉ dùng khi đã review phạm vi, security rules và chi phí.

### Các bước thực hiện

1. **Kiểm tra cấu hình hiện có.** Từ `dev/lab/`, đọc module call và networking module. Xác định VPC, route, subnet, SG/NACL hiện có và resource addresses trong Terraform state. Nếu SG đã tồn tại, chỉnh sửa đúng resource sở hữu; không khai báo cùng một AWS security group ở hai state.

2. **Xác định luồng được phép trước khi viết rule.** Ghi rõ các bên, direction, protocol, destination port, source và lý do nghiệp vụ. Ví dụ:

   | Luồng | Direction ở SG đích | Protocol/port | Source |
   |---|---|---|---|
   | Client đến ALB listener | Inbound ALB SG | TCP 443 | CIDR client được duyệt; `0.0.0.0/0` chỉ khi dịch vụ thực sự public |
   | ALB đến ứng dụng | Inbound application SG | TCP 8080 | ALB SG |
   | Ứng dụng đến database | Inbound database SG | TCP 3306 | Application SG |

   Traffic response của kết nối được phép được SG stateful xử lý; không thêm inbound “any ephemeral ports” chỉ để nhận response. Nếu workload phải chủ động gọi một dịch vụ khác, khai báo egress rule riêng và xác định dịch vụ đích.

3. **Tạo security group với tên và mô tả thể hiện mục đích.** Ví dụ sau giả định networking module đang quản lý VPC thông qua `aws_vpc.this`. Nếu VPC thuộc module khác, truyền `vpc_id` qua input thay vì tạo VPC trùng:

   ```hcl
   resource "aws_security_group" "alb" {
     name        = "${var.environment_name}-alb"
     description = "Controls inbound HTTPS and ALB-to-application traffic"
     vpc_id      = aws_vpc.this.id

     egress = []

     tags = {
       Name        = "${var.environment_name}-alb"
       Environment = var.environment_name
     }
   }

   resource "aws_security_group" "application" {
     name        = "${var.environment_name}-application"
     description = "Allows application traffic only from the ALB security group"
     vpc_id      = aws_vpc.this.id

     egress = []

     tags = {
       Name        = "${var.environment_name}-application"
       Environment = var.environment_name
     }
   }

   resource "aws_security_group" "database" {
     name        = "${var.environment_name}-database"
     description = "Allows database traffic only from the application security group"
     vpc_id      = aws_vpc.this.id

     egress = []

     tags = {
       Name        = "${var.environment_name}-database"
       Environment = var.environment_name
     }
   }
   ```

   `egress = []` thể hiện chủ đích không giữ rule outbound mặc định rộng trong các SG này; các egress rule được khai báo riêng ở bước sau. AWS provider khuyến nghị không trộn inline ingress/egress blocks với các resource rule độc lập cho cùng một SG. Dùng nhất quán một kiểu quản lý rule theo provider/version dự án.

4. **Khai báo rule inbound theo nguồn thực sự cần thiết.** Với AWS provider hiện đại, rule riêng giúp mỗi rule có lifecycle/address rõ ràng:

   ```hcl
   resource "aws_vpc_security_group_ingress_rule" "alb_https" {
     security_group_id = aws_security_group.alb.id
     cidr_ipv4         = var.alb_client_cidr
     from_port         = 443
     to_port           = 443
     ip_protocol       = "tcp"
     description       = "HTTPS from approved clients"
   }

   resource "aws_vpc_security_group_ingress_rule" "application_from_alb" {
     security_group_id            = aws_security_group.application.id
     referenced_security_group_id = aws_security_group.alb.id
     from_port                    = var.application_port
     to_port                      = var.application_port
     ip_protocol                  = "tcp"
     description                  = "Application traffic from the ALB"
   }

   resource "aws_vpc_security_group_ingress_rule" "database_from_application" {
     security_group_id            = aws_security_group.database.id
     referenced_security_group_id = aws_security_group.application.id
     from_port                    = var.database_port
     to_port                      = var.database_port
     ip_protocol                  = "tcp"
     description                  = "Database traffic from the application"
   }
   ```

   `var.alb_client_cidr` cần được kiểm tra và chỉ dùng `0.0.0.0/0` khi ALB được thiết kế public. Không tạo rule SSH/RDP hoặc database từ Internet. Security group reference biểu diễn nguồn là network interface mang SG được tham chiếu; nó không thay xác thực ở tầng ứng dụng.

5. **Khai báo egress có mục đích.** Ví dụ minh họa application cần gọi database TCP 3306 và HTTPS TCP 443 để tải dependency hoặc gọi API được phê duyệt:

   ```hcl
   resource "aws_vpc_security_group_egress_rule" "application_to_database" {
     security_group_id            = aws_security_group.application.id
     referenced_security_group_id = aws_security_group.database.id
     from_port                    = var.database_port
     to_port                      = var.database_port
     ip_protocol                  = "tcp"
     description                  = "Application connections to the database"
   }

   resource "aws_vpc_security_group_egress_rule" "application_https" {
     security_group_id = aws_security_group.application.id
     cidr_ipv4         = var.approved_https_destination_cidr
     from_port         = 443
     to_port           = 443
     ip_protocol       = "tcp"
     description       = "HTTPS egress to approved destinations"
   }
   ```

   CIDR egress không lọc theo DNS domain; public endpoint IP có thể thay đổi. Nếu cần egress theo domain/service, đánh giá VPC endpoints, proxy/firewall, managed prefix lists hoặc phương án phù hợp khác. ALB cũng cần egress đến app/health-check target theo thiết kế; database thường không cần egress rộng, nhưng yêu cầu thực tế như backup/monitoring phải được xác định thay vì cắt bỏ mù quáng.

6. **Định nghĩa biến với validation phù hợp.** Khai báo `environment_name`, `application_port`, `database_port`, `alb_client_cidr` và `approved_https_destination_cidr` trong module variables/root interface. Cung cấp mẫu CIDR không nhạy cảm trong `terraform.tfvars.example`. Port phải nằm trong phạm vi hợp lệ; CIDR phải parse được và được đối chiếu với quy hoạch mạng. Validation cú pháp không chứng minh CIDR được phép hoặc service thực sự cần mở.

7. **Nối output để section sau dùng lại.** Có thể xuất các SG ID cần module compute/database:

   ```hcl
   output "alb_security_group_id" {
     description = "Security group dành cho ALB."
     value       = aws_security_group.alb.id
   }

   output "application_security_group_id" {
     description = "Security group dành cho application workload."
     value       = aws_security_group.application.id
   }

   output "database_security_group_id" {
     description = "Security group dành cho database workload."
     value       = aws_security_group.database.id
   }
   ```

   Chỉ thêm output tương ứng resource thật trong module. Output ID không phải secret nhưng vẫn nên được tiêu thụ qua module interface thay vì hard-code ID ở nhiều nơi.

8. **Phân tích NACL hiện có ở chế độ đọc.** Trong Console, ghi lại NACL associations và rule ingress/egress theo thứ tự. Với một flow được chọn, lập bảng request/response, direction, CIDR, protocol và port. Đánh dấu rule đầu tiên khớp. Không sửa ACL hoặc subnet association trong bài thực hành dùng chung này.

   Nếu cần mô phỏng NACL custom, hãy tạo một bảng rule trên giấy hoặc file ghi chú không chứa dữ liệu nhạy cảm, gồm allow traffic nghiệp vụ, return traffic/ephemeral ports, rule Deny nếu thực sự cần và implicit deny cuối danh sách. Chỉ chuyển thành Terraform resource khi đã có topology đầy đủ và change plan/rollback được review.

9. **Format, init và validate.** Từ `dev/lab/`, chạy:

   ```powershell
   terraform fmt -recursive
   terraform init
   terraform validate
   ```

   Không chuyển backend/state để chạy riêng bài này. Xác minh provider đang dùng hỗ trợ resource rule đã chọn; không trộn inline rule và standalone rule cho cùng security group.

10. **Review plan.** Chạy `terraform plan` và kiểm tra:

   - Đúng account, Region, `dev/lab/` root module, backend và state.
   - SG chỉ tạo các luồng đã ghi trong bảng; không có ingress `0.0.0.0/0` cho SSH/RDP/database.
   - SG application chỉ nhận từ SG ALB trên port ứng dụng; SG database chỉ nhận từ SG application trên port DB.
   - Outbound có đúng CIDR/port dự kiến; không có all-egress ngoài ý muốn.
   - Không có resource VPC, route, subnet, NACL hoặc association bị thay/xóa ngoài phạm vi.
   - Mọi thay đổi SG đã hiểu rõ tác động nếu SG được gắn vào interface hiện có; rule có thể có hiệu lực ngay.

   Nếu plan thêm rule mở rộng, thay thế SG, xóa rule hiện có hoặc đụng NACL association, dừng và điều tra trước khi apply.

11. **Apply chỉ khi an toàn và cần thiết.** Nếu SG sẽ được gắn vào workload đang chạy, cần change window/approval phù hợp; apply có thể mở hoặc chặn traffic ngay. Nếu chưa có workload hoặc chưa được phê duyệt, có thể dừng ở validate/plan và hoàn thành phân tích NACL bằng Console. Không thay NACL để tạo một kết quả “thực nghiệm” trên subnet dùng chung.

### Xác minh kết quả

- Nếu chỉ chạy plan, xác minh các rule dự kiến đúng với bảng luồng; chưa kết luận kết nối thực tế hoạt động.
- Nếu apply đã được phê duyệt, trên Console mở SG và xác minh inbound/outbound rules, description, VPC, tag, cũng như các resource/network interface đang gắn group.
- Kiểm tra kết quả âm tính bằng review rule: client không nằm trong CIDR/SG được cho phép không có rule inbound tương ứng; database không có rule từ Internet; quản trị không được mở toàn cầu.
- Lần theo các NACL association và rules theo thứ tự. Xác định request lẫn response khớp rule nào; nếu không có rule phù hợp thì implicit deny.
- Nếu có workload test được phê duyệt, kiểm tra đúng port/protocol từ nguồn đúng, kiểm tra health check, ứng dụng và logs; không dùng một bài test thành công để kết luận mọi nguồn đều bị chặn.
- Dùng VPC Flow Logs hoặc công cụ quan sát phù hợp nếu cần chẩn đoán traffic được accept/reject; xác nhận retention, chi phí và quyền truy cập logs.
- Không gửi dữ liệu nhạy cảm, credentials hoặc thông tin người dùng thật trong test.

### Xử lý lỗi thường gặp

| Triệu chứng | Nguyên nhân có thể có | Cách kiểm tra và khắc phục |
|---|---|---|
| Kết nối timeout dù SG có inbound rule | Thiếu route, NACL chặn, SG khác/port/protocol sai, host firewall hoặc ứng dụng không lắng nghe | Kiểm tra route và association, SG gắn với ENI, NACL hai chiều, listener và logs theo từng chặng. |
| Request đến ALB nhưng health check fail | SG ALB egress/app ingress không khớp port hoặc health-check path/protocol sai | Xác minh health-check port/protocol, ALB SG egress đến app SG và app SG ingress từ ALB SG. |
| App không kết nối được database | DB SG thiếu inbound từ app SG, port sai, subnet/route/DNS hoặc credentials/database health có vấn đề | Kiểm tra SG reference, DB listener/port, route/local connectivity, DNS và trạng thái DB; không mở database ra Internet để thử. |
| Outbound request được gửi nhưng không có response | NACL stateless thiếu rule chiều về/ephemeral port, route hoặc egress policy không phù hợp | Vẽ packet hai chiều, kiểm tra rule NACL đầu tiên khớp, CIDR và ephemeral port theo client/service. |
| Rule Deny của NACL không có hiệu lực như mong đợi | Có rule số nhỏ hơn đã Allow traffic trước đó | Sắp xếp theo số thứ tự và xác định rule đầu tiên khớp; plan trước khi đổi thứ tự. |
| SG mới cho phép egress rộng hơn mong muốn | Outbound mặc định vẫn tồn tại hoặc có một SG khác gắn vào ENI chứa rule rộng | Kiểm tra tất cả SG trên network interface và Terraform ownership; rule Allow được hợp nhất, không có SG Deny để phủ định. |
| Terraform báo duplicate rule hoặc drift | Inline và standalone rules cùng quản lý, resource đã tạo ngoài Terraform hoặc state không khớp | Kiểm tra provider version, resource addresses, state và Console; chuẩn hóa ownership/migration có kế hoạch, không xóa state thủ công. |
| Sau khi sửa NACL nhiều subnet mất kết nối | NACL gắn với nhiều subnet và rule stateless không đủ cho mọi flow | Xác định subnet association và flow bị ảnh hưởng; dùng quy trình rollback đã review, không thay đổi thêm tùy tiện trong production. |

### Dọn dẹp tài nguyên

Security group có thể đã được xuất cho các section compute/database tiếp theo hoặc được gắn vào workload; không xóa chỉ vì kết thúc bài 5. NACL hiện có và association subnet là tài nguyên dùng chung, không thay hoặc xóa trong bước cleanup của bài này.

Nếu SG thử nghiệm chỉ được tạo cho một thử nghiệm riêng và chủ sở hữu xác nhận có thể xóa:

1. Xác nhận SG thuộc đúng `dev/lab/` state và không được resource/module khác tham chiếu hoặc gắn vào ENI.
2. Đọc plan xóa; xác minh không ảnh hưởng SG dùng chung hoặc workload đang chạy.
3. Chỉ apply deletion sau khi có xác nhận rõ ràng cho đúng resource.
4. Xác minh rule và group đã được dọn; không chạy destroy toàn bộ root `dev/lab/`.

Không áp dụng quy trình này cho prod. Thay đổi prod cần phê duyệt, review bảo mật, kế hoạch triển khai và rollback riêng.

## 7. Bài tập tự kiểm tra

1. Nêu ít nhất ba điểm khác nhau giữa security group và network ACL về phạm vi, state, Allow/Deny và cách xử lý rule.
2. Một EC2 trong private subnet khởi tạo TCP kết nối đến server HTTPS trên port 443. SG outbound cho phép TCP 443 và SG stateful. Vì sao thông thường không cần inbound SG mở toàn bộ ephemeral ports, nhưng NACL vẫn phải có rule response phù hợp?
3. ALB public gọi application trên TCP 8080; application gọi database trên TCP 3306. Thiết kế inbound rule cho ba SG và giải thích vì sao nên dùng SG reference cho hai chặng nội bộ.
4. Một NACL có rule số 90 Allow TCP 443 từ `203.0.113.0/24` và rule số 100 Deny mọi protocol từ cùng CIDR. Traffic HTTPS từ CIDR đó được xử lý thế nào? Nếu đổi thứ tự số thành 80 cho Deny và 100 cho Allow thì sao?
5. Một database SG có inbound rule TCP 3306 từ `0.0.0.0/0`, còn một SG khác chỉ cho phép từ application SG. Vì sao không thể dựa vào SG thứ hai để chặn quyền rộng của SG thứ nhất?
6. NACL subnet cho phép inbound TCP 443 nhưng không có outbound rule phù hợp. Vì sao một HTTPS connection có thể không hoạt động dù inbound rule đã Allow?

### Gợi ý đáp án

1. SG gắn ở network interface, stateful, chỉ Allow và tập hợp rule của nhiều SG được hợp nhất. NACL gắn ở subnet, stateless, có Allow/Deny, rule số thấp được xét trước và cần rule hai chiều. Route table chọn next hop, không phải firewall.
2. SG theo dõi connection state nên response thuộc outbound connection được cho phép không cần inbound rule độc lập kiểu stateless. NACL không theo dõi trạng thái; response là packet theo chiều ngược, destination port là ephemeral port của client, nên phải được NACL chiều tương ứng cho phép.
3. ALB SG inbound TCP 443 từ client CIDR được duyệt; application SG inbound TCP 8080 từ ALB SG; database SG inbound TCP 3306 từ application SG. SG reference diễn tả quan hệ workload và tránh phụ thuộc IP động, giảm phạm vi nguồn so với CIDR rộng.
4. Rule số 90 Allow khớp trước, nên traffic được Allow và rule 100 không được xét. Nếu Deny là rule 80, Deny khớp trước và traffic bị chặn dù rule 100 Allow.
5. Security group không có explicit Deny; các Allow từ mọi SG gắn lên ENI được hợp lại. SG chặt hơn không phủ định SG rộng. Cần gỡ hoặc giới hạn rule rộng và rà soát tất cả group được gắn.
6. NACL stateless, request và response được đánh giá riêng. Inbound rule chỉ cho phép chiều vào; outbound response cần được một outbound rule cho phép, bao gồm port/CIDR phù hợp. Nếu thiếu, response bị chặn.

## Tổng kết kiến thức và nguyên tắc áp dụng

Route table, security group và network ACL trả lời ba câu hỏi khác nhau: packet đi đâu, workload nào được nhận/gửi traffic, và traffic nào được qua subnet boundary. Chẩn đoán kết nối nên lần theo toàn bộ đường đi và cả hai chiều, không dừng ở việc thấy một inbound rule có vẻ phù hợp.

Security group thường là lớp kiểm soát chi tiết theo workload: stateful, dễ mô hình hóa quan hệ bằng SG reference và chỉ Allow. Vì nhiều SG được hợp nhất, một rule rộng ở bất kỳ SG nào đang gắn vào ENI vẫn có thể mở traffic. Network ACL là lớp stateless theo subnet với Allow/Deny và thứ tự rule; cần tính response/ephemeral ports và đặc biệt cẩn trọng với association có blast radius lớn.

Thiết kế tốt bắt đầu từ luồng nghiệp vụ, sau đó định nghĩa protocol/port/nguồn tối thiểu, triển khai bằng Terraform có ownership rõ, đọc plan, xác minh cả trường hợp được phép và bị chặn. Không mở cổng quản trị/database ra Internet, không dùng NACL hoặc SG thay IAM/TLS/xác thực ứng dụng và không sửa firewall trên mạng dùng chung khi chưa đánh giá tác động.

Hãy xem xét một hệ thống mới có public ALB, application ở hai AZ và database Multi-AZ. Bạn sẽ chia SG theo vai trò thế nào, dùng NACL ở đâu, cần rule nào cho health check/response, và bằng chứng gì sẽ giúp bạn xác nhận rằng database không thể được truy cập trực tiếp từ Internet?