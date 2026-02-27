terraform{
required_version=">= 1.5.0"
}

locals{
  greeting="hello"
}

output "greeting"{
value=local.greeting
}

