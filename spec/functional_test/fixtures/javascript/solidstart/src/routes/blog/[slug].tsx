import { useParams } from "@solidjs/router";

export default function Post() {
  const params = useParams();
  return <article>{params.slug}</article>;
}
