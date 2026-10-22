import { Text } from "react-native";

// A screen, not an API route: the verb export must not become an endpoint.
export function GET() {
  return null;
}

export default function Home() {
  return <Text>Home</Text>;
}
