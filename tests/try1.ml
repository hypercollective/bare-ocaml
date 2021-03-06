
module E = Example1

let () =
  print_endline ">>> run encoding test 1";
  let p1 = E.Person.Customer
      {E.Customer. name="foo"; email="foo@bar.com";
       orders=[|{E.Customer_orders_0.orderId=97L; quantity=106l}|];
       metadata=Bare.String_map.singleton "mood" (Bytes.of_string "jolly good!");
       address={E.Address.address=[|"123"; "lol road"; "so"; "far away"|];
                city="Paris"; state="là bas"; country="Eurozone 51";
               }
      } in
  let s = Bare.to_string E.Person.encode p1 in
  begin
    let oc = open_out "foo.data" in
    output_string oc s; flush oc;
    close_out oc;
  end;
  let p2 = Bare.of_string_exn E.Person.decode s in
  let s2 = Bare.to_string E.Person.encode p2 in
  begin
    let oc = open_out "foo2.data" in
    output_string oc s2; flush oc;
    close_out oc;
  end;
  assert (s = s2);
  assert (p1 = p2);
  ()

