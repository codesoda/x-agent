pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

#[cfg(test)]
mod tests {
    use super::add;

    #[test]
    fn adds_correctly() {
        assert_eq!(add(2, 2), 4);
    }

    #[test]
    fn deliberately_fails() {
        assert_eq!(add(2, 2), 5, "this test is meant to fail");
    }
}
