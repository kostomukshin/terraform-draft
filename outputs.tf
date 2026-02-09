output "alb_dns_name" { value = aws_lb.wp.dns_name }
output "rds_endpoint" { value = aws_db_instance.wp.address }
output "jenkins_public_ip" { value = aws_instance.jenkins.public_ip }
